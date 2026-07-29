"""
One-off bulk load of historical season data from the vaastav/Fantasy-Premier-League
GitHub archive (https://github.com/vaastav/Fantasy-Premier-League), which the
official FPL API doesn't expose (bootstrap-static's history_past is season
summaries only, not gameweek-level detail).

Lands three files per season into raw:
- gws/merged_gw.csv    -> raw.historical_gw_stats_snapshot (per-player-gameweek stats)
- players_raw.csv      -> raw.historical_players_snapshot (that season's player list,
                          including the cross-season-stable `code` field and
                          set-piece order fields)
- teams.csv            -> raw.historical_teams_snapshot (that season's team list,
                          including the cross-season-stable `code` field, needed to
                          resolve opponent_team ids in merged_gw.csv)

Usage:
    python scripts/ingest_historical.py                          # default seasons
    python scripts/ingest_historical.py --seasons 2023-24 2024-25 # specific seasons
"""

import argparse
import csv
import io

import requests
from psycopg2.extras import Json

from db import get_connection

RAW_BASE_URL = "https://raw.githubusercontent.com/vaastav/Fantasy-Premier-League/master/data"
HEADERS = {"User-Agent": "fpl-data-warehouse/0.1 (personal project)"}

DEFAULT_SEASONS = ["2021-22", "2022-23", "2023-24", "2024-25", "2025-26"]


def fetch_csv_rows(url: str) -> list[dict]:
    resp = requests.get(url, headers=HEADERS, timeout=60)
    resp.raise_for_status()
    reader = csv.DictReader(io.StringIO(resp.text))
    return list(reader)


def ingest_historical_gw_stats(conn, season: str) -> None:
    rows = fetch_csv_rows(f"{RAW_BASE_URL}/{season}/gws/merged_gw.csv")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.historical_gw_stats_snapshot (season, payload) VALUES (%s, %s)",
            (season, Json(rows)),
        )
    conn.commit()
    print(f"{season}: {len(rows)} player-gameweek rows")


def ingest_historical_players(conn, season: str) -> None:
    rows = fetch_csv_rows(f"{RAW_BASE_URL}/{season}/players_raw.csv")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.historical_players_snapshot (season, payload) VALUES (%s, %s)",
            (season, Json(rows)),
        )
    conn.commit()
    print(f"{season}: {len(rows)} players")


def ingest_historical_teams(conn, season: str) -> None:
    rows = fetch_csv_rows(f"{RAW_BASE_URL}/{season}/teams.csv")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.historical_teams_snapshot (season, payload) VALUES (%s, %s)",
            (season, Json(rows)),
        )
    conn.commit()
    print(f"{season}: {len(rows)} teams")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seasons", nargs="+", default=DEFAULT_SEASONS,
                         help=f"seasons to load, e.g. 2023-24 2024-25 (default: {DEFAULT_SEASONS})")
    args = parser.parse_args()

    conn = get_connection()
    try:
        for season in args.seasons:
            ingest_historical_players(conn, season)
            ingest_historical_teams(conn, season)
            ingest_historical_gw_stats(conn, season)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
