# FPL Data Warehouse

Fantasy Premier League data project. First step: land raw data from the
official FPL API into a Postgres bronze layer.

## Setup

Requires a local Postgres server (database `fpl` already created) and Python 3.

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env   # adjust credentials if needed
psql -d fpl -f sql/init_database.sql
```

## Ingest raw data

```bash
.venv/bin/python scripts/ingest_raw.py
```

Pulls three endpoints from `https://fantasy.premierleague.com/api/`:

- `bootstrap-static/` — teams, players, gameweeks (events), positions (element types)
- `fixtures/` — full season fixture list
- `element-summary/{id}/` — per-player gameweek-by-gameweek history

## Bronze layer

Schema: `bronze`. Each ingestion run **appends** a new snapshot row
(`fetched_at` + raw `payload` JSONB) rather than overwriting previous data,
so re-running the script periodically builds a history of price, ownership,
and points changes across the season:

- `bronze.bootstrap_static_snapshot`
- `bronze.fixtures_snapshot`
- `bronze.element_summary_snapshot` (one row per player per run)

Data is kept as raw JSONB on purpose — no typing/flattening yet. That's the
next step (silver layer).
