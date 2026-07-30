"""
Given an existing squad, decides which transfers (if any) to make this
gameweek via a MILP solve (PuLP + CBC): weighs expected-points gain against
the -4 point cost of any transfer beyond the free ones available, subject
to the budget actually available (bank + sell value of transferred-out
players, using FPL's real 50% sell-on-fee rule confirmed in this project's
own raw.bootstrap_static_snapshot game_settings: transfers_sell_on_fee=0.5,
max_extra_free_transfers=4, i.e. free transfers bank up to 5 total).

Squad membership decisions use marts.fct_player_expected_points_horizon
(season-aware), same principle as optimize_squad.py -- who you own is a
season-long decision. Lineup/captain (Stage 2) still uses the
single-gameweek score.

Current squad source (in priority order):
1. marts.fct_entry_picks for FPL_ENTRY_ID at the latest gameweek with real
   data -- once GW1 has been played and re-ingested, this is authoritative.
2. Falls back to the latest run in optimizer.squad_recommendations (i.e.
   this project's own prior recommendation) as a stand-in, using its
   logged price as each player's purchase price. This is what happens
   right now, pre-season -- treat results as a simulation/demo of the
   mechanics, not real advice, until real squad data exists.

Purchase price (needed for the sell-on-fee calc) is derived, in priority
order: (a) marts.fct_entry_transfers' element_in_cost for anyone acquired
via a real transfer, (b) the price logged in optimizer.squad_recommendations
for players believed to be part of the original squad, (c) current market
price as a last resort (assumes no profit/loss -- flagged as an
approximation until real purchase-price data exists).

--wildcard removes the free-transfer/hit-cost constraint entirely (an
unlimited rebuild, matching what playing a Wildcard chip actually does).

Usage:
    python scripts/optimize_transfers.py                        # normal transfer decision
    python scripts/optimize_transfers.py --free-transfers 2      # override FT count
    python scripts/optimize_transfers.py --bank 1.5              # override bank
    python scripts/optimize_transfers.py --wildcard              # unlimited rebuild, no hit cost
    python scripts/optimize_transfers.py --no-persist
"""

import argparse

import pulp

from db import get_connection
from optimizer_common import (
    MAX_PER_CLUB, SQUAD_COMPOSITION, SQUAD_SIZE,
    fetch_players, persist, print_squad, solve_lineup,
)

FREE_TRANSFER_CAP = 5   # 1 base + max_extra_free_transfers=4, confirmed in game_settings
HIT_COST = 4


def fetch_current_squad_with_purchase_prices(conn, entry_id: int):
    """Returns (list of player_codes, {player_code: purchase_price}, source_label)."""
    with conn.cursor() as cur:
        cur.execute("""
            select player_code from marts.fct_entry_picks
            where entry_id = %s and gameweek_id = (
                select max(gameweek_id) from marts.fct_entry_picks where entry_id = %s
            )
        """, (entry_id, entry_id))
        real_squad = [row[0] for row in cur.fetchall()]

    if real_squad:
        purchase_prices = {}
        with conn.cursor() as cur:
            for code in real_squad:
                cur.execute("""
                    select player_in_cost from marts.fct_entry_transfers
                    where entry_id = %s and player_in_code = %s
                    order by transferred_at desc limit 1
                """, (entry_id, code))
                row = cur.fetchone()
                purchase_prices[code] = float(row[0]) if row else None
        return real_squad, purchase_prices, "fct_entry_picks (real)"

    with conn.cursor() as cur:
        cur.execute("""
            select player_code, price from optimizer.squad_recommendations
            where generated_at = (select max(generated_at) from optimizer.squad_recommendations)
        """)
        rows = cur.fetchall()
    if not rows:
        raise RuntimeError(
            "No current squad found: fct_entry_picks is empty and there's no prior "
            "optimizer.squad_recommendations run. Run optimize_squad.py first."
        )
    squad_codes = [r[0] for r in rows]
    purchase_prices = {r[0]: float(r[1]) for r in rows}
    return squad_codes, purchase_prices, "optimizer.squad_recommendations (simulated -- no real squad yet)"


def sell_value(current_price: float, purchase_price: float) -> float:
    """FPL's 50% sell-on-fee rule: only half of any price-rise profit is
    kept on sale; losses are absorbed in full. Computed in integer tenths
    of a million to match FPL's own price precision."""
    current_tenths = round(current_price * 10)
    purchase_tenths = round(purchase_price * 10)
    if current_tenths > purchase_tenths:
        profit_tenths = current_tenths - purchase_tenths
        return (purchase_tenths + profit_tenths // 2) / 10.0
    return current_tenths / 10.0


def solve_transfers(
    players: list[dict],
    current_squad: list[int],
    purchase_prices: dict[int, float],
    bank: float,
    free_transfers: int,
) -> tuple[list[int], int, float]:
    """Returns (new_squad_codes, hits_taken, net_cost_of_hits)."""
    prob = pulp.LpProblem("fpl_transfer_selection", pulp.LpMaximize)

    codes = [p["player_code"] for p in players]
    by_code = {p["player_code"]: p for p in players}
    horizon_xpts = {c: float(by_code[c]["horizon_expected_points"]) for c in codes}
    current_squad_set = set(current_squad)

    new_squad = pulp.LpVariable.dicts("new_squad", codes, cat="Binary")
    extra_transfers = pulp.LpVariable("extra_transfers", lowBound=0, cat="Integer")

    prob += (
        pulp.lpSum(new_squad[c] * horizon_xpts[c] for c in codes)
        - HIT_COST * extra_transfers
    )

    prob += pulp.lpSum(new_squad[c] for c in codes) == SQUAD_SIZE

    for position_id, count in SQUAD_COMPOSITION.items():
        prob += pulp.lpSum(new_squad[c] for c in codes if by_code[c]["position_id"] == position_id) == count

    clubs = {by_code[c]["current_team_code"] for c in codes}
    for club in clubs:
        prob += pulp.lpSum(new_squad[c] for c in codes if by_code[c]["current_team_code"] == club) <= MAX_PER_CLUB

    sell_values = {
        c: sell_value(float(by_code[c]["current_price"]), purchase_prices.get(c, float(by_code[c]["current_price"])))
        for c in current_squad_set
    }
    prob += (
        bank
        + pulp.lpSum(sell_values[c] * (1 - new_squad[c]) for c in current_squad_set)
        - pulp.lpSum(float(by_code[c]["current_price"]) * new_squad[c] for c in codes if c not in current_squad_set)
        >= 0
    )

    transfers_out = pulp.lpSum(1 - new_squad[c] for c in current_squad_set)
    prob += extra_transfers >= transfers_out - free_transfers

    prob.solve(pulp.PULP_CBC_CMD(msg=False))
    if pulp.LpStatus[prob.status] != "Optimal":
        raise RuntimeError(f"transfer solver did not find an optimal solution: {pulp.LpStatus[prob.status]}")

    new_squad_codes = [c for c in codes if new_squad[c].value() > 0.5]
    hits = round(extra_transfers.value())
    return new_squad_codes, hits, hits * HIT_COST


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entry-id", type=int, default=None, help="defaults to FPL_ENTRY_ID env var")
    parser.add_argument("--free-transfers", type=int, default=1)
    parser.add_argument("--bank", type=float, default=None, help="override bank; default derived from squad source")
    parser.add_argument("--wildcard", action="store_true", help="unlimited rebuild, no hit cost")
    parser.add_argument("--no-persist", action="store_true")
    args = parser.parse_args()

    import os
    entry_id = args.entry_id or int(os.environ["FPL_ENTRY_ID"])

    conn = get_connection()
    try:
        players = fetch_players(conn)
        gameweek_id = players[0]["gameweek_id"]

        current_squad, purchase_prices, source = fetch_current_squad_with_purchase_prices(conn, entry_id)
        print(f"Current squad source: {source}")

        by_code = {p["player_code"]: p for p in players}
        bank = args.bank
        if bank is None:
            spent = sum(purchase_prices.get(c, float(by_code[c]["current_price"])) for c in current_squad)
            bank = round(100.0 - spent, 1)
        free_transfers = SQUAD_SIZE if args.wildcard else args.free_transfers

        print(f"Bank: £{bank:.1f}m, free transfers: {'unlimited (wildcard)' if args.wildcard else free_transfers}")

        new_squad_codes, hits, hit_cost = solve_transfers(
            players, current_squad, purchase_prices, bank, free_transfers,
        )

        transferred_out = [c for c in current_squad if c not in new_squad_codes]
        transferred_in = [c for c in new_squad_codes if c not in current_squad]

        if transferred_out:
            print("\n=== TRANSFERS ===")
            for out_c, in_c in zip(transferred_out, transferred_in):
                print(f"  OUT: {by_code[out_c]['web_name']:<16} -> IN: {by_code[in_c]['web_name']}")
            print(f"  Hits taken: {hits} (-{hit_cost} points)" if hits else "  No hits taken (within free transfers)")
        else:
            print("\n=== TRANSFERS ===\n  None recommended -- current squad is already optimal.")

        result = solve_lineup(players, new_squad_codes)
        print_squad(result)
        print(f"Net predicted points after hit cost: {result['total_expected_points'] - hit_cost:.2f}")

        if not args.no_persist:
            persist(conn, result, gameweek_id)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
