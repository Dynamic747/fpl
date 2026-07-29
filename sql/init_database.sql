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
