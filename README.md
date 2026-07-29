# FPL Data Warehouse

Fantasy Premier League data project: EL (Python) lands raw API data into
Postgres, dbt transforms it through staging → intermediate → marts layers.

## Setup

Requires a local Postgres server (database `fpl` already created) and Python 3.

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env   # adjust credentials/FPL_ENTRY_ID
psql -d fpl -f sql/init_database.sql
```

dbt needs a `~/.dbt/profiles.yml` profile named `fpl` targeting the same
Postgres database (not committed — see `transform/dbt_project.yml` for the
expected `profile: 'fpl'` name).

## Ingest raw data (EL)

```bash
.venv/bin/python scripts/ingest_raw.py
```

Pulls from `https://fantasy.premierleague.com/api/`:

- `bootstrap-static/` — teams, players, gameweeks (events), positions (element types)
- `fixtures/` — full season fixture list
- `element-summary/{id}/` — per-player gameweek-by-gameweek history
- `entry/{FPL_ENTRY_ID}/` and `entry/{FPL_ENTRY_ID}/history/` — manager profile and season history
- `entry/{FPL_ENTRY_ID}/event/{gw}/picks/` — squad picks for a gameweek (pass `--picks-event N`; 404s until that gameweek's deadline passes)
- `entry/{FPL_ENTRY_ID}/transfers/` — manager's transfer log

## Ingest historical seasons (one-off bulk load)

```bash
.venv/bin/python scripts/ingest_historical.py
```

The official API only exposes gameweek-level detail for the *current*
season. For model training data across past seasons, this bulk-loads CSVs
from the [vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League)
GitHub archive (default: last 5 completed seasons — pass `--seasons` to
change). Player identity across seasons isn't stable via `id` (FPL reassigns
it each season) — use the `code` field instead, which vaastav's
`players_raw.csv` also includes.

## Raw schema

Schema: `raw`. Each ingestion run **appends** a new snapshot row
(`fetched_at` + raw `payload` JSONB) rather than overwriting previous data,
so re-running the script periodically builds a history of price, ownership,
and points changes across the season:

- `raw.bootstrap_static_snapshot`, `raw.fixtures_snapshot`
- `raw.element_summary_snapshot` (one row per player per run)
- `raw.entry_snapshot`, `raw.entry_history_snapshot`, `raw.entry_picks_snapshot`, `raw.entry_transfers_snapshot`
- `raw.historical_players_snapshot`, `raw.historical_gw_stats_snapshot` (one row per season per load)

## Transform (dbt)

dbt project lives in `transform/`, following standard staging/intermediate/marts
convention:

```bash
cd transform
../.venv/bin/dbt run
../.venv/bin/dbt test
```

- `models/staging/fpl/stg_fpl__*` — thin 1:1 models over the `raw` sources,
  selecting the latest snapshot per key and doing light typing/renaming only.
  Materialized as views in the `staging` schema.
- `models/intermediate/` — not yet built. Will hold joined/derived logic
  (e.g. rolling form, fixture-adjusted expected points) that isn't yet a
  business-facing mart.
- `models/marts/` — not yet built. Final fact/dimension tables the
  prediction model and squad optimizer will query against. Materialized as
  tables in the `marts` schema.
