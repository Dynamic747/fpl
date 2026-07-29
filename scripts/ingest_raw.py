"""
Pulls raw data from the official Fantasy Premier League API and lands it,
unmodified, into the bronze schema of the fpl Postgres database.

Each run inserts new snapshot rows rather than overwriting previous ones, so
the bronze layer accumulates a history of how prices, ownership, and points
changed over the season.

Usage:
    python scripts/ingest_raw.py                  # full run (bootstrap, fixtures, all players)
    python scripts/ingest_raw.py --skip-players    # skip the slow per-player loop
    python scripts/ingest_raw.py --limit 20        # only ingest the first 20 players (testing)
"""

import argparse
import json
import time

import requests
from psycopg2.extras import Json

from db import get_connection

BASE_URL = "https://fantasy.premierleague.com/api"
HEADERS = {"User-Agent": "fpl-data-warehouse/0.1 (personal project)"}


def fetch_json(url: str) -> dict | list:
    resp = requests.get(url, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    return resp.json()


def ingest_bootstrap_static(conn) -> dict:
    payload = fetch_json(f"{BASE_URL}/bootstrap-static/")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO bronze.bootstrap_static_snapshot (payload) VALUES (%s)",
            (Json(payload),),
        )
    conn.commit()
    print(f"bootstrap-static: {len(payload['elements'])} players, "
          f"{len(payload['teams'])} teams, {len(payload['events'])} gameweeks")
    return payload


def ingest_fixtures(conn) -> None:
    payload = fetch_json(f"{BASE_URL}/fixtures/")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO bronze.fixtures_snapshot (payload) VALUES (%s)",
            (Json(payload),),
        )
    conn.commit()
    print(f"fixtures: {len(payload)} fixtures")


def ingest_element_summaries(conn, element_ids: list[int], delay: float = 0.3) -> None:
    with conn.cursor() as cur:
        for i, element_id in enumerate(element_ids, start=1):
            payload = fetch_json(f"{BASE_URL}/element-summary/{element_id}/")
            cur.execute(
                "INSERT INTO bronze.element_summary_snapshot (element_id, payload) "
                "VALUES (%s, %s)",
                (element_id, Json(payload)),
            )
            if i % 50 == 0 or i == len(element_ids):
                conn.commit()
                print(f"element-summary: {i}/{len(element_ids)}")
            time.sleep(delay)
    conn.commit()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-players", action="store_true",
                         help="skip fetching per-player element-summary data")
    parser.add_argument("--limit", type=int, default=None,
                         help="only ingest the first N players (for testing)")
    args = parser.parse_args()

    conn = get_connection()
    try:
        bootstrap = ingest_bootstrap_static(conn)
        ingest_fixtures(conn)

        if not args.skip_players:
            element_ids = [e["id"] for e in bootstrap["elements"]]
            if args.limit:
                element_ids = element_ids[: args.limit]
            ingest_element_summaries(conn, element_ids)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
