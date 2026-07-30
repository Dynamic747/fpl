"""
Evaluates chip timing (Wildcard, Bench Boost, Triple Captain, Free Hit)
against the CURRENT squad, using marts.fct_player_expected_points_by_gameweek
across the visible prediction horizon (default 8 gameweeks).

IMPORTANT CAVEAT: the confirmed 2026-27 rule is one of each chip per half
of the season (through the GW19 deadline, then a fresh set for GW20-38,
no rollover -- see project memory). The visible horizon here only reaches
~8 gameweeks, well short of the 19-week first-half window. There is also,
as of this run, no known double or blank gameweek anywhere in the fixture
list -- those get created by fixture rearrangements confirmed much later
in the season. So this is NOT a "use chip X on gameweek Y" schedule --
it's a snapshot of the best candidate *within what's currently visible*,
which should be re-run regularly and will change completely once a real
DGW/BGW appears. Default recommendation is to HOLD every chip unless a
value clearly stands out.

Per-chip evaluation, for each gameweek g in the horizon:
- Bench Boost value(g): current squad's total expected points that week
  MINUS its best starting-XI value that week (i.e. exactly what the 4
  benched players would additionally contribute).
- Triple Captain value(g): current squad's best starting player's expected
  points that week (what captaincy already doubles -- TC adds one more
  copy of this on top).
- Free Hit value(g): (best possible ANY-15-player squad's starting-XI
  value that week) MINUS (current squad's actual starting-XI value that
  week). This is the "opportunity cost" of not having a Free-Hit-optimal
  team just for that week -- meaningful even without a literal blank
  gameweek, though it spikes hardest during one.
- Wildcard value: NOT gameweek-specific like the others -- it's about
  whether the current squad has drifted enough from optimal that an
  unlimited zero-hit-cost rebuild beats what optimize_transfers.py would
  already recommend via ordinary (hit-costed) transfers. Computed by
  reusing optimize_transfers.solve_transfers in both normal and --wildcard
  mode and comparing the net outcome.

Usage:
    python scripts/chip_strategy.py
    python scripts/chip_strategy.py --no-persist
"""

import argparse

import pulp

from db import get_connection
from optimizer_common import MAX_PER_CLUB, SQUAD_COMPOSITION, SQUAD_SIZE, fetch_players, solve_lineup
from optimize_transfers import fetch_current_squad_with_purchase_prices, solve_transfers


def fetch_by_gameweek(conn):
    with conn.cursor() as cur:
        cur.execute("""
            select player_code, web_name, position_id, current_team_code,
                   current_price, gameweek_id, expected_points
            from marts.fct_player_expected_points_by_gameweek
            order by gameweek_id, player_code
        """)
        columns = [c.name for c in cur.description]
        rows = [dict(zip(columns, row)) for row in cur.fetchall()]

    by_gameweek: dict[int, list[dict]] = {}
    for row in rows:
        by_gameweek.setdefault(row["gameweek_id"], []).append(row)
    return by_gameweek


def solve_squad_for_scores(players: list[dict], xpts_by_code: dict[int, float], budget: float = 100.0) -> list[int]:
    """Same constraint structure as optimize_squad.solve_squad, but scored
    against an arbitrary {player_code: expected_points} map instead of the
    season-aware horizon score -- used here to find the single-gameweek-
    optimal squad (what Free Hit would let you pick) for a specific week."""
    prob = pulp.LpProblem("fpl_squad_for_week", pulp.LpMaximize)

    codes = [p["player_code"] for p in players]
    by_code = {p["player_code"]: p for p in players}

    squad = pulp.LpVariable.dicts("squad", codes, cat="Binary")
    prob += pulp.lpSum(squad[c] * xpts_by_code[c] for c in codes)

    prob += pulp.lpSum(squad[c] for c in codes) == SQUAD_SIZE
    prob += pulp.lpSum(squad[c] * float(by_code[c]["current_price"]) for c in codes) <= budget

    for position_id, count in SQUAD_COMPOSITION.items():
        prob += pulp.lpSum(squad[c] for c in codes if by_code[c]["position_id"] == position_id) == count

    clubs = {by_code[c]["current_team_code"] for c in codes}
    for club in clubs:
        prob += pulp.lpSum(squad[c] for c in codes if by_code[c]["current_team_code"] == club) <= MAX_PER_CLUB

    prob.solve(pulp.PULP_CBC_CMD(msg=False))
    if pulp.LpStatus[prob.status] != "Optimal":
        raise RuntimeError(f"squad-for-week solver did not find an optimal solution: {pulp.LpStatus[prob.status]}")

    return [c for c in codes if squad[c].value() > 0.5]


def best_xi_value(players: list[dict], squad_codes: list[int], xpts_by_code: dict[int, float]) -> float:
    result = solve_lineup(players, squad_codes, xpts_override=xpts_by_code)
    # solve_lineup's total_expected_points double-counts the captain (by
    # design, for real lineup output) -- undo that here since we just want
    # the XI's raw value for comparison purposes.
    return result["total_expected_points"] - xpts_by_code[result["captain_code"]]


def evaluate_gameweek(players_this_gw: list[dict], current_squad: list[int]) -> dict:
    xpts = {p["player_code"]: float(p["expected_points"]) for p in players_this_gw}

    current_total = sum(xpts[c] for c in current_squad)
    current_xi_value = best_xi_value(players_this_gw, current_squad, xpts)
    bench_boost_value = current_total - current_xi_value

    lineup = solve_lineup(players_this_gw, current_squad, xpts_override=xpts)
    triple_captain_value = xpts[lineup["captain_code"]]

    optimal_squad = solve_squad_for_scores(players_this_gw, xpts)
    optimal_xi_value = best_xi_value(players_this_gw, optimal_squad, xpts)
    free_hit_value = optimal_xi_value - current_xi_value

    return {
        "bench_boost_value": bench_boost_value,
        "triple_captain_value": triple_captain_value,
        "triple_captain_player": lineup["by_code"][lineup["captain_code"]]["web_name"],
        "free_hit_value": free_hit_value,
    }


def persist(conn, wildcard_gain, best_bb, best_tc, best_fh):
    rows = [
        ("wildcard", None, wildcard_gain, "extra points vs. ordinary hit-costed transfers, if played now"),
        ("bench_boost", best_bb["gameweek_id"], best_bb["bench_boost_value"], "best candidate within visible horizon"),
        ("triple_captain", best_tc["gameweek_id"], best_tc["triple_captain_value"], best_tc["triple_captain_player"]),
        ("free_hit", best_fh["gameweek_id"], best_fh["free_hit_value"], "best candidate within visible horizon"),
    ]
    with conn.cursor() as cur:
        cur.executemany(
            """
            insert into optimizer.chip_opportunities (chip_name, gameweek_id, opportunity_value, detail)
            values (%s, %s, %s, %s)
            """,
            rows,
        )
    conn.commit()
    print(f"\nPersisted {len(rows)} rows to optimizer.chip_opportunities")


def main():
    import os

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entry-id", type=int, default=None, help="defaults to FPL_ENTRY_ID env var")
    parser.add_argument("--free-transfers", type=int, default=1)
    parser.add_argument("--no-persist", action="store_true")
    args = parser.parse_args()

    entry_id = args.entry_id or int(os.environ["FPL_ENTRY_ID"])

    conn = get_connection()
    try:
        players = fetch_players(conn)
        current_squad, purchase_prices, source = fetch_current_squad_with_purchase_prices(conn, entry_id)
        print(f"Current squad source: {source}\n")

        by_gameweek = fetch_by_gameweek(conn)

        print("Evaluating chip opportunities across the visible horizon...")
        results = {}
        for gw, players_this_gw in sorted(by_gameweek.items()):
            results[gw] = evaluate_gameweek(players_this_gw, current_squad)

        best_bb_gw = max(results, key=lambda g: results[g]["bench_boost_value"])
        best_tc_gw = max(results, key=lambda g: results[g]["triple_captain_value"])
        best_fh_gw = max(results, key=lambda g: results[g]["free_hit_value"])

        print("\n=== BENCH BOOST -- best candidates in visible horizon ===")
        for gw in sorted(results, key=lambda g: -results[g]["bench_boost_value"])[:3]:
            print(f"  GW{gw}: +{results[gw]['bench_boost_value']:.2f} pts from bench")

        print("\n=== TRIPLE CAPTAIN -- best candidates in visible horizon ===")
        for gw in sorted(results, key=lambda g: -results[g]["triple_captain_value"])[:3]:
            r = results[gw]
            print(f"  GW{gw}: {r['triple_captain_player']} projected {r['triple_captain_value']:.2f} pts (extra copy on top of normal captain double)")

        print("\n=== FREE HIT -- best candidates in visible horizon ===")
        for gw in sorted(results, key=lambda g: -results[g]["free_hit_value"])[:3]:
            print(f"  GW{gw}: +{results[gw]['free_hit_value']:.2f} pts vs. your actual squad that week")

        by_code = {p["player_code"]: p for p in players}
        bank = round(100.0 - sum(purchase_prices.get(c, float(by_code[c]["current_price"])) for c in current_squad), 1)
        normal_squad, _, normal_hit_cost = solve_transfers(players, current_squad, purchase_prices, bank, args.free_transfers)
        wildcard_squad, _, _ = solve_transfers(players, current_squad, purchase_prices, bank, SQUAD_SIZE)

        normal_value = sum(float(by_code[c]["horizon_expected_points"]) for c in normal_squad) - normal_hit_cost
        wildcard_value = sum(float(by_code[c]["horizon_expected_points"]) for c in wildcard_squad)
        wildcard_gain = wildcard_value - normal_value

        print("\n=== WILDCARD ===")
        print(f"  Ordinary transfers (with hit costs) horizon value: {normal_value:.2f}")
        print(f"  Full wildcard rebuild horizon value:               {wildcard_value:.2f}")
        print(f"  Wildcard's incremental value right now:            {wildcard_gain:.2f}")
        if wildcard_gain < 4:
            print("  -> Not worth it yet: ordinary transfers can reach nearly the same place for free/cheap.")
        else:
            print("  -> Worth watching: a real gap is opening up between your squad and the optimal one.")

        print(
            "\nReminder: this only sees the next "
            f"{len(results)} gameweeks, not the full first-half chip window (through GW19), "
            "and no double/blank gameweek exists in the fixture list yet. Hold chips and re-run "
            "this regularly -- don't lock in a gameweek from this alone."
        )

        if not args.no_persist:
            persist(
                conn, wildcard_gain,
                {"gameweek_id": best_bb_gw, **results[best_bb_gw]},
                {"gameweek_id": best_tc_gw, **results[best_tc_gw]},
                {"gameweek_id": best_fh_gw, **results[best_fh_gw]},
            )
    finally:
        conn.close()


if __name__ == "__main__":
    main()
