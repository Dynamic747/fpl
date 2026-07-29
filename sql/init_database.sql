/*
Create the raw schema in the fpl database.

The raw schema is an append-only landing zone: every ingestion run inserts
a new snapshot row (raw JSON payload + fetched_at) rather than overwriting
previous data. This preserves history of price/ownership/points changes
across the season and is resilient to the FPL API adding/removing fields.

dbt's staging models (models/staging/fpl) treat these tables as sources.
*/

CREATE SCHEMA IF NOT EXISTS raw;

-- Full bootstrap-static payload (teams, players, gameweeks, positions all nested inside)
CREATE TABLE IF NOT EXISTS raw.bootstrap_static_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

-- Full fixtures payload (array of all fixtures for the season)
CREATE TABLE IF NOT EXISTS raw.fixtures_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

-- Per-player element-summary payload (history, upcoming fixtures, history_past)
CREATE TABLE IF NOT EXISTS raw.element_summary_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    element_id INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_element_summary_element_id
    ON raw.element_summary_snapshot (element_id, fetched_at);

-- Manager (entry) profile: team value, overall points/rank, favourite team
CREATE TABLE IF NOT EXISTS raw.entry_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_snapshot_entry_id
    ON raw.entry_snapshot (entry_id, fetched_at);

-- Manager's season-by-season history and chip usage
CREATE TABLE IF NOT EXISTS raw.entry_history_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_history_snapshot_entry_id
    ON raw.entry_history_snapshot (entry_id, fetched_at);

-- Manager's squad picks for a given gameweek (404s until that gameweek's deadline passes)
CREATE TABLE IF NOT EXISTS raw.entry_picks_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    event_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_picks_snapshot_entry_event
    ON raw.entry_picks_snapshot (entry_id, event_id, fetched_at);
