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
use optimize_transfers.py instead.

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
from optimizer_common import MAX_PER_CLUB, SQUAD_COMPOSITION, SQUAD_SIZE, fetch_players, persist, print_squad, solve_lineup


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
