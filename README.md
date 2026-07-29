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
- `raw.historical_players_snapshot`, `raw.historical_teams_snapshot`, `raw.historical_gw_stats_snapshot` (one row per season per load)

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
- `models/intermediate/int_player_gameweek_performance_unioned` — unions
  current-season live stats with 5 seasons of historical stats, resolving
  both to the stable `player_code`/`team_code` identifiers (FPL reassigns
  `id` every season, so current and historical rows use different id spaces).
- `models/intermediate/int_player_recent_form` — recency-weighted per-90
  rate stats per player (0.55 decay per season back), blending current
  season with up to 5 historical seasons. Naturally falls back to
  last-season/career form pre-season (e.g. GW1) with no separate
  cold-start logic.
- `seeds/scoring_rules.csv` — FPL's position-based point values (goals,
  assists, clean sheets, cards, etc.), loaded via `dbt seed`.
- `models/marts/` — dimensional model (Kimball-style, natural keys, no
  surrogate keys given the data volume):
  - `dim_players`, `dim_teams` — conformed across current + historical
    seasons. Players/teams no longer in the Premier League still appear
    (with null current-state attributes) so historical facts always have
    somewhere to join — a current-only dimension would orphan every
    relegated club and departed player. `dim_teams.strength_*` falls back
    to a team's last historical season's rating (then league average)
    since the API reports 0 for every team pre-season.
  - `dim_positions`, `dim_gameweeks`
  - `fct_player_gameweek_performance` — grain: player × season × gameweek.
    The training-data fact table.
  - `fct_fixtures` — grain: fixture × season. Current season only.
  - `fct_entry_gameweek_performance`, `fct_entry_picks`, `fct_entry_transfers`
    — your manager account: points/rank/bank per gameweek, squad picks,
    transfer log.
  - `fct_player_expected_points` — grain: one row per current-squad
    player, predicting the next unplayed gameweek. Statistical formula
    (not ML): shrinks `int_player_recent_form` toward a positional
    baseline by sample size, then scales by expected minutes and a
    fixture-difficulty multiplier. Handles blank/double gameweeks via
    `fixture_count`. See the model file's header comment for known v1
    simplifications (no bonus-points/BPS modeling, no defensive-contribution
    rule, no rotation/team-news signal beyond `chance_of_playing_next_round`).

  All materialized as tables in the `marts` schema.
