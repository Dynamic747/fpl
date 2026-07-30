"""Shared constants and lineup/persist logic used by both optimize_squad.py
(initial squad construction) and optimize_transfers.py (ongoing transfer
decisions)."""

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


def solve_lineup(players: list[dict], squad_codes: list[int], xpts_override: dict[int, float] = None) -> dict:
    """Given a fixed 15-man squad, pick a gameweek's starting XI + captain by
    single-gameweek score (captaincy/lineup should reflect that week's
    fixtures, not a discounted season-wide score).

    xpts_override lets callers evaluate a *different* gameweek than "next"
    (e.g. chip_strategy.py scanning the whole horizon) by supplying
    {player_code: expected_points for that week} instead of relying on
    each player's gw_expected_points field, which is always "next gameweek"."""
    import pulp

    prob = pulp.LpProblem("fpl_lineup_selection", pulp.LpMaximize)

    by_code = {p["player_code"]: p for p in players}
    codes = squad_codes
    gw_xpts = xpts_override or {c: float(by_code[c]["gw_expected_points"]) for c in codes}

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
