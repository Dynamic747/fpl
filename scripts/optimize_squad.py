"""
Picks the optimal 15-man FPL squad via a two-stage MILP solve (PuLP + CBC):

  Stage 1 (squad):    which 15 players to OWN, using
                       marts.fct_player_expected_points_horizon (season-aware,
                       discounted sum over the next several gameweeks) --
                       who you own is a season-long decision, not a
                       one-week one.
  Stage 2 (lineup):   given that fixed 15, who STARTS and who's CAPTAIN
                       this specific gameweek, using
                       marts.fct_player_expected_points (single-gameweek) --
                       captaincy and lineup should reflect this week's
                       fixtures, not a discounted season-wide score.

This is squad *construction* (no existing squad, no transfers) — the
right problem for GW1. From GW2 onward, once there's an existing squad,
this becomes a transfer-decision problem instead (a separate script, not
built yet). Re-run just Stage 2 each week even once a squad exists, since
lineup/captain should always use that week's fixtures.

Constraints:
- Squad: exactly 15 players (2 GK, 5 DEF, 5 MID, 3 FWD), total cost <=
  budget (default 100.0m), max 3 players per real club
- Lineup: exactly 11 starters (1 GK, 3-5 DEF, 2-5 MID, 1-3 FWD), 1 captain

Usage:
    python scripts/optimize_squad.py                 # solve + print + persist
    python scripts/optimize_squad.py --budget 99.5    # different budget
    python scripts/optimize_squad.py --no-persist     # print only, don't write to Postgres
"""

import argparse

import pulp

from db import get_connection

POSITION_NAMES = {1: "GK", 2: "DEF", 3: "MID", 4: "FWD"}
SQUAD_COMPOSITION = {1: 2, 2: 5, 3: 5, 4: 3}
STARTING_XI_MIN = {1: 1, 2: 3, 3: 2, 4: 1}
STARTING_XI_MAX = {1: 1, 2: 5, 3: 5, 4: 3}
MAX_PER_CLUB = 3
SQUAD_SIZE = 15
STARTING_XI_SIZE = 11


def fetch_players(conn):
    with conn.cursor() as cur:
        cur.execute("""
            select h.player_code, h.web_name, h.position_id, h.current_team_code,
                   h.current_price, h.horizon_expected_points, e.expected_points as gw_expected_points,
                   e.gameweek_id
            from marts.fct_player_expected_points_horizon h
            inner join marts.fct_player_expected_points e on h.player_code = e.player_code
            order by h.horizon_expected_points desc
        """)
        columns = [c.name for c in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]


def solve_squad(players: list[dict], budget: float) -> list[int]:
    """Stage 1: pick the 15-man squad by season-aware horizon score."""
    prob = pulp.LpProblem("fpl_squad_selection", pulp.LpMaximize)

    codes = [p["player_code"] for p in players]
    by_code = {p["player_code"]: p for p in players}
    horizon_xpts = {c: float(by_code[c]["horizon_expected_points"]) for c in codes}

    squad = pulp.LpVariable.dicts("squad", codes, cat="Binary")

    prob += pulp.lpSum(squad[c] * horizon_xpts[c] for c in codes)

    prob += pulp.lpSum(squad[c] for c in codes) == SQUAD_SIZE
    prob += pulp.lpSum(squad[c] * float(by_code[c]["current_price"]) for c in codes) <= budget

    for position_id, count in SQUAD_COMPOSITION.items():
        prob += pulp.lpSum(squad[c] for c in codes if by_code[c]["position_id"] == position_id) == count

    clubs = {by_code[c]["current_team_code"] for c in codes}
    for club in clubs:
        prob += pulp.lpSum(squad[c] for c in codes if by_code[c]["current_team_code"] == club) <= MAX_PER_CLUB

    prob.solve(pulp.PULP_CBC_CMD(msg=False))
    if pulp.LpStatus[prob.status] != "Optimal":
        raise RuntimeError(f"squad solver did not find an optimal solution: {pulp.LpStatus[prob.status]}")

    return [c for c in codes if squad[c].value() > 0.5]


def solve_lineup(players: list[dict], squad_codes: list[int]) -> dict:
    """Stage 2: given the fixed squad, pick this week's starting XI + captain
    by single-gameweek score."""
    prob = pulp.LpProblem("fpl_lineup_selection", pulp.LpMaximize)

    by_code = {p["player_code"]: p for p in players}
    codes = squad_codes
    gw_xpts = {c: float(by_code[c]["gw_expected_points"]) for c in codes}

    start = pulp.LpVariable.dicts("start", codes, cat="Binary")
    captain = pulp.LpVariable.dicts("captain", codes, cat="Binary")

    prob += (
        pulp.lpSum(start[c] * gw_xpts[c] for c in codes)
        + pulp.lpSum(captain[c] * gw_xpts[c] for c in codes)
    )

    prob += pulp.lpSum(start[c] for c in codes) == STARTING_XI_SIZE
    for position_id in SQUAD_COMPOSITION:
        position_starters = pulp.lpSum(start[c] for c in codes if by_code[c]["position_id"] == position_id)
        prob += position_starters >= STARTING_XI_MIN[position_id]
        prob += position_starters <= STARTING_XI_MAX[position_id]

    prob += pulp.lpSum(captain[c] for c in codes) == 1
    for c in codes:
        prob += captain[c] <= start[c]

    prob.solve(pulp.PULP_CBC_CMD(msg=False))
    if pulp.LpStatus[prob.status] != "Optimal":
        raise RuntimeError(f"lineup solver did not find an optimal solution: {pulp.LpStatus[prob.status]}")

    starting_codes = [c for c in codes if start[c].value() > 0.5]
    captain_code = next(c for c in codes if captain[c].value() > 0.5)
    bench_codes = [c for c in codes if c not in starting_codes]

    vice_captain_code = max(
        (c for c in starting_codes if c != captain_code),
        key=lambda c: gw_xpts[c],
    )

    bench_gk = [c for c in bench_codes if by_code[c]["position_id"] == 1]
    bench_outfield = sorted(
        (c for c in bench_codes if by_code[c]["position_id"] != 1),
        key=lambda c: gw_xpts[c],
        reverse=True,
    )

    return {
        "squad_codes": codes,
        "starting_codes": starting_codes,
        "bench_ordered": bench_outfield + bench_gk,
        "captain_code": captain_code,
        "vice_captain_code": vice_captain_code,
        "total_cost": sum(float(by_code[c]["current_price"]) for c in codes),
        "total_expected_points": sum(gw_xpts[c] for c in starting_codes) + gw_xpts[captain_code],
        "by_code": by_code,
    }


def print_squad(result: dict) -> None:
    by_code = result["by_code"]

    def fmt(code):
        p = by_code[code]
        tag = ""
        if code == result["captain_code"]:
            tag = " (C)"
        elif code == result["vice_captain_code"]:
            tag = " (VC)"
        return (
            f"  {p['web_name']:<16} {POSITION_NAMES[p['position_id']]:<4} £{float(p['current_price']):.1f}m"
            f"  xPts(GW)={float(p['gw_expected_points']):.2f}  xPts(horizon)={float(p['horizon_expected_points']):.2f}{tag}"
        )

    print("\n=== STARTING XI ===")
    for position_id in (1, 2, 3, 4):
        starters = [c for c in result["starting_codes"] if by_code[c]["position_id"] == position_id]
        starters.sort(key=lambda c: by_code[c]["gw_expected_points"], reverse=True)
        for c in starters:
            print(fmt(c))

    print("\n=== BENCH (priority order) ===")
    for c in result["bench_ordered"]:
        print(fmt(c))

    print(f"\nTotal squad cost: £{result['total_cost']:.1f}m")
    print(f"Predicted GW starting XI points (incl. captain double): {result['total_expected_points']:.2f}")


def persist(conn, result: dict, gameweek_id: int) -> None:
    by_code = result["by_code"]
    rows = []
    for c in result["starting_codes"]:
        p = by_code[c]
        rows.append((
            gameweek_id, c, p["web_name"], p["position_id"], p["current_team_code"],
            p["current_price"], p["gw_expected_points"], "starting", None,
            c == result["captain_code"], c == result["vice_captain_code"],
            result["total_cost"], result["total_expected_points"],
        ))
    for order, c in enumerate(result["bench_ordered"], start=1):
        p = by_code[c]
        rows.append((
            gameweek_id, c, p["web_name"], p["position_id"], p["current_team_code"],
            p["current_price"], p["gw_expected_points"], "bench", order,
            False, False,
            result["total_cost"], result["total_expected_points"],
        ))

    with conn.cursor() as cur:
        cur.executemany(
            """
            insert into optimizer.squad_recommendations
                (gameweek_id, player_code, web_name, position_id, team_code,
                 price, expected_points, squad_role, bench_order,
                 is_captain, is_vice_captain, total_squad_cost, total_expected_points)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            rows,
        )
    conn.commit()
    print(f"\nPersisted {len(rows)} rows to optimizer.squad_recommendations (gameweek_id={gameweek_id})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--budget", type=float, default=100.0)
    parser.add_argument("--no-persist", action="store_true")
    args = parser.parse_args()

    conn = get_connection()
    try:
        players = fetch_players(conn)
        gameweek_id = players[0]["gameweek_id"]
        squad_codes = solve_squad(players, args.budget)
        result = solve_lineup(players, squad_codes)
        print_squad(result)
        if not args.no_persist:
            persist(conn, result, gameweek_id)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
