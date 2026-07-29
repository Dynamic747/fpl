"""
Picks the optimal 15-man FPL squad for the next gameweek from
marts.fct_player_expected_points, using a MILP solve (PuLP + CBC).

This is squad *construction* (no existing squad, no transfers) — the
right problem for GW1. From GW2 onward, once there's an existing squad,
this becomes a transfer-decision problem instead (a separate script, not
built yet).

Constraints:
- Exactly 15 players: 2 GK, 5 DEF, 5 MID, 3 FWD
- Total cost <= budget (default 100.0m)
- Max 3 players per real club
- Starting XI: exactly 11 (1 GK, 3-5 DEF, 2-5 MID, 1-3 FWD)
- Exactly 1 captain, chosen from the starting XI

Objective: maximize sum(expected_points for the starting 11) + captain's
expected_points once more (captaining doubles their points).

Usage:
    python scripts/optimize_squad.py                 # solve + print + persist
    python scripts/optimize_squad.py --budget 99.5    # different budget
    python scripts/optimize_squad.py --no-persist     # print only, don't write to Postgres
"""

import argparse

import pulp
from psycopg2.extras import Json

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
            select e.player_code, e.web_name, e.position_id, e.current_team_code,
                   e.current_price, e.expected_points, e.gameweek_id
            from marts.fct_player_expected_points e
            order by e.expected_points desc
        """)
        columns = [c.name for c in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]


def solve_squad(players: list[dict], budget: float) -> dict:
    prob = pulp.LpProblem("fpl_squad_selection", pulp.LpMaximize)

    codes = [p["player_code"] for p in players]
    by_code = {p["player_code"]: p for p in players}

    squad = pulp.LpVariable.dicts("squad", codes, cat="Binary")
    start = pulp.LpVariable.dicts("start", codes, cat="Binary")
    captain = pulp.LpVariable.dicts("captain", codes, cat="Binary")

    xpts = {c: float(by_code[c]["expected_points"]) for c in codes}

    prob += (
        pulp.lpSum(start[c] * xpts[c] for c in codes)
        + pulp.lpSum(captain[c] * xpts[c] for c in codes)
    )

    prob += pulp.lpSum(squad[c] for c in codes) == SQUAD_SIZE
    prob += pulp.lpSum(squad[c] * float(by_code[c]["current_price"]) for c in codes) <= budget

    for position_id, count in SQUAD_COMPOSITION.items():
        prob += pulp.lpSum(squad[c] for c in codes if by_code[c]["position_id"] == position_id) == count

    clubs = {by_code[c]["current_team_code"] for c in codes}
    for club in clubs:
        prob += pulp.lpSum(squad[c] for c in codes if by_code[c]["current_team_code"] == club) <= MAX_PER_CLUB

    prob += pulp.lpSum(start[c] for c in codes) == STARTING_XI_SIZE
    for c in codes:
        prob += start[c] <= squad[c]

    for position_id in SQUAD_COMPOSITION:
        position_starters = pulp.lpSum(start[c] for c in codes if by_code[c]["position_id"] == position_id)
        prob += position_starters >= STARTING_XI_MIN[position_id]
        prob += position_starters <= STARTING_XI_MAX[position_id]

    prob += pulp.lpSum(captain[c] for c in codes) == 1
    for c in codes:
        prob += captain[c] <= start[c]

    prob.solve(pulp.PULP_CBC_CMD(msg=False))

    if pulp.LpStatus[prob.status] != "Optimal":
        raise RuntimeError(f"solver did not find an optimal solution: {pulp.LpStatus[prob.status]}")

    squad_codes = [c for c in codes if squad[c].value() > 0.5]
    starting_codes = [c for c in codes if start[c].value() > 0.5]
    captain_code = next(c for c in codes if captain[c].value() > 0.5)
    bench_codes = [c for c in squad_codes if c not in starting_codes]

    # vice-captain: highest xPts starter after the captain (simple backup rule,
    # no need for a separate MILP variable)
    vice_captain_code = max(
        (c for c in starting_codes if c != captain_code),
        key=lambda c: xpts[c],
    )

    # bench order: outfield subs by descending xPts, reserve GK always last
    bench_gk = [c for c in bench_codes if by_code[c]["position_id"] == 1]
    bench_outfield = sorted(
        (c for c in bench_codes if by_code[c]["position_id"] != 1),
        key=lambda c: xpts[c],
        reverse=True,
    )
    bench_ordered = bench_outfield + bench_gk

    return {
        "squad_codes": squad_codes,
        "starting_codes": starting_codes,
        "bench_ordered": bench_ordered,
        "captain_code": captain_code,
        "vice_captain_code": vice_captain_code,
        "total_cost": sum(float(by_code[c]["current_price"]) for c in squad_codes),
        "total_expected_points": (
            sum(xpts[c] for c in starting_codes) + xpts[captain_code]
        ),
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
        return f"  {p['web_name']:<16} {POSITION_NAMES[p['position_id']]:<4} £{float(p['current_price']):.1f}m  xPts={float(p['expected_points']):.2f}{tag}"

    print("\n=== STARTING XI ===")
    for position_id in (1, 2, 3, 4):
        starters = [c for c in result["starting_codes"] if by_code[c]["position_id"] == position_id]
        starters.sort(key=lambda c: by_code[c]["expected_points"], reverse=True)
        for c in starters:
            print(fmt(c))

    print("\n=== BENCH (priority order) ===")
    for c in result["bench_ordered"]:
        print(fmt(c))

    print(f"\nTotal squad cost: £{result['total_cost']:.1f}m")
    print(f"Predicted starting XI points (incl. captain double): {result['total_expected_points']:.2f}")


def persist(conn, result: dict, gameweek_id: int) -> None:
    by_code = result["by_code"]
    rows = []
    for c in result["starting_codes"]:
        p = by_code[c]
        rows.append((
            gameweek_id, c, p["web_name"], p["position_id"], p["current_team_code"],
            p["current_price"], p["expected_points"], "starting", None,
            c == result["captain_code"], c == result["vice_captain_code"],
            result["total_cost"], result["total_expected_points"],
        ))
    for order, c in enumerate(result["bench_ordered"], start=1):
        p = by_code[c]
        rows.append((
            gameweek_id, c, p["web_name"], p["position_id"], p["current_team_code"],
            p["current_price"], p["expected_points"], "bench", order,
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
        result = solve_squad(players, args.budget)
        print_squad(result)
        if not args.no_persist:
            persist(conn, result, gameweek_id)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
