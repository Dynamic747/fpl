"""
Pulls raw data from the official Fantasy Premier League API and lands it,
unmodified, into the raw schema of the fpl Postgres database.

Each run inserts new snapshot rows rather than overwriting previous ones, so
the raw schema accumulates a history of how prices, ownership, and points
changed over the season.

Usage:
    python scripts/ingest_raw.py                  # full run (bootstrap, fixtures, all players)
    python scripts/ingest_raw.py --skip-players    # skip the slow per-player loop
    python scripts/ingest_raw.py --limit 20        # only ingest the first 20 players (testing)
    python scripts/ingest_raw.py --entry-id 2148914 --picks-event 1   # also try a picks pull
"""

import argparse
import json
import os
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


def fetch_json_or_none(url: str) -> dict | list | None:
    """Like fetch_json, but returns None on 404 instead of raising.

    Used for endpoints that 404 until something unlocks them (e.g. a
    manager's picks aren't visible until that gameweek's deadline passes).
    """
    resp = requests.get(url, headers=HEADERS, timeout=30)
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()


def ingest_bootstrap_static(conn) -> dict:
    payload = fetch_json(f"{BASE_URL}/bootstrap-static/")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.bootstrap_static_snapshot (payload) VALUES (%s)",
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
            "INSERT INTO raw.fixtures_snapshot (payload) VALUES (%s)",
            (Json(payload),),
        )
    conn.commit()
    print(f"fixtures: {len(payload)} fixtures")


def ingest_element_summaries(conn, element_ids: list[int], delay: float = 0.3) -> None:
    with conn.cursor() as cur:
        for i, element_id in enumerate(element_ids, start=1):
            payload = fetch_json(f"{BASE_URL}/element-summary/{element_id}/")
            cur.execute(
                "INSERT INTO raw.element_summary_snapshot (element_id, payload) "
                "VALUES (%s, %s)",
                (element_id, Json(payload)),
            )
            if i % 50 == 0 or i == len(element_ids):
                conn.commit()
                print(f"element-summary: {i}/{len(element_ids)}")
            time.sleep(delay)
    conn.commit()


def ingest_entry(conn, entry_id: int) -> None:
    payload = fetch_json(f"{BASE_URL}/entry/{entry_id}/")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.entry_snapshot (entry_id, payload) VALUES (%s, %s)",
            (entry_id, Json(payload)),
        )
    conn.commit()
    print(f"entry {entry_id}: {payload.get('player_first_name')} "
          f"{payload.get('player_last_name')}")


def ingest_entry_history(conn, entry_id: int) -> None:
    payload = fetch_json(f"{BASE_URL}/entry/{entry_id}/history/")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.entry_history_snapshot (entry_id, payload) VALUES (%s, %s)",
            (entry_id, Json(payload)),
        )
    conn.commit()
    print(f"entry {entry_id} history: {len(payload.get('past', []))} past seasons, "
          f"{len(payload.get('chips', []))} chips used")


def ingest_entry_picks(conn, entry_id: int, event_id: int) -> None:
    """Best-effort: picks aren't available via the API until that
    gameweek's deadline has passed, so a 404 here is expected pre-deadline
    and is skipped rather than treated as an error."""
    payload = fetch_json_or_none(f"{BASE_URL}/entry/{entry_id}/event/{event_id}/picks/")
    if payload is None:
        print(f"entry {entry_id} picks for GW{event_id}: not available yet (404)")
        return
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.entry_picks_snapshot (entry_id, event_id, payload) "
            "VALUES (%s, %s, %s)",
            (entry_id, event_id, Json(payload)),
        )
    conn.commit()
    print(f"entry {entry_id} picks for GW{event_id}: {len(payload.get('picks', []))} picks")


def ingest_entry_transfers(conn, entry_id: int) -> None:
    payload = fetch_json(f"{BASE_URL}/entry/{entry_id}/transfers/")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO raw.entry_transfers_snapshot (entry_id, payload) VALUES (%s, %s)",
            (entry_id, Json(payload)),
        )
    conn.commit()
    print(f"entry {entry_id} transfers: {len(payload)} transfers made")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-players", action="store_true",
                         help="skip fetching per-player element-summary data")
    parser.add_argument("--limit", type=int, default=None,
                         help="only ingest the first N players (for testing)")
    parser.add_argument("--entry-id", type=int, default=os.environ.get("FPL_ENTRY_ID"),
                         help="manager entry id to ingest (defaults to FPL_ENTRY_ID env var)")
    parser.add_argument("--picks-event", type=int, default=None,
                         help="also attempt to pull this gameweek's picks for --entry-id")
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

        if args.entry_id:
            ingest_entry(conn, args.entry_id)
            ingest_entry_history(conn, args.entry_id)
            ingest_entry_transfers(conn, args.entry_id)
            if args.picks_event:
                ingest_entry_picks(conn, args.entry_id, args.picks_event)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
