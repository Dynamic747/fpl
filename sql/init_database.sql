/*
Create the bronze schema in the fpl database.

The bronze layer is an append-only landing zone: every ingestion run inserts
a new snapshot row (raw JSON payload + fetched_at) rather than overwriting
previous data. This preserves history of price/ownership/points changes
across the season and is resilient to the FPL API adding/removing fields.
*/

CREATE SCHEMA IF NOT EXISTS bronze;

-- Full bootstrap-static payload (teams, players, gameweeks, positions all nested inside)
CREATE TABLE IF NOT EXISTS bronze.bootstrap_static_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

-- Full fixtures payload (array of all fixtures for the season)
CREATE TABLE IF NOT EXISTS bronze.fixtures_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

-- Per-player element-summary payload (history, upcoming fixtures, history_past)
CREATE TABLE IF NOT EXISTS bronze.element_summary_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    element_id INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_element_summary_element_id
    ON bronze.element_summary_snapshot (element_id, fetched_at);

-- Manager (entry) profile: team value, overall points/rank, favourite team
CREATE TABLE IF NOT EXISTS bronze.entry_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_snapshot_entry_id
    ON bronze.entry_snapshot (entry_id, fetched_at);

-- Manager's season-by-season history and chip usage
CREATE TABLE IF NOT EXISTS bronze.entry_history_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_history_snapshot_entry_id
    ON bronze.entry_history_snapshot (entry_id, fetched_at);

-- Manager's squad picks for a given gameweek (404s until that gameweek's deadline passes)
CREATE TABLE IF NOT EXISTS bronze.entry_picks_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    event_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_picks_snapshot_entry_event
    ON bronze.entry_picks_snapshot (entry_id, event_id, fetched_at);
