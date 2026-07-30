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

-- Manager's transfer log (player in/out, cost, timestamp)
CREATE TABLE IF NOT EXISTS raw.entry_transfers_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entry_transfers_snapshot_entry_id
    ON raw.entry_transfers_snapshot (entry_id, fetched_at);

-- Historical seasons bulk-loaded from the vaastav/Fantasy-Premier-League
-- GitHub archive (the official API only exposes the current season's
-- gameweek-level detail). One row per season per load.
CREATE TABLE IF NOT EXISTS raw.historical_gw_stats_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    season     TEXT NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_historical_gw_stats_snapshot_season
    ON raw.historical_gw_stats_snapshot (season, fetched_at);

-- Historical seasons' player list (players_raw.csv), including the
-- season-specific element id, the cross-season stable `code`, and
-- set-piece order fields.
CREATE TABLE IF NOT EXISTS raw.historical_players_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    season     TEXT NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_historical_players_snapshot_season
    ON raw.historical_players_snapshot (season, fetched_at);

-- Historical seasons' team list (teams.csv), including the season-specific
-- team id and the cross-season stable `code` — needed to resolve
-- opponent_team (a season-specific id in historical_gw_stats_snapshot)
-- back to a stable team identity.
CREATE TABLE IF NOT EXISTS raw.historical_teams_snapshot (
    id         BIGSERIAL PRIMARY KEY,
    season     TEXT NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_historical_teams_snapshot_season
    ON raw.historical_teams_snapshot (season, fetched_at);

/*
Squad optimizer output. Populated by scripts/optimize_squad.py (a MILP
solve, not a dbt model — dbt only manages derived SQL transformations, this
is an external decision). Each run inserts 15 rows (one per squad slot)
tagged with generated_at, so recommendations are kept as a history rather
than overwritten.
*/
CREATE SCHEMA IF NOT EXISTS optimizer;

CREATE TABLE IF NOT EXISTS optimizer.squad_recommendations (
    id                     BIGSERIAL PRIMARY KEY,
    generated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    gameweek_id            INTEGER NOT NULL,
    player_code            INTEGER NOT NULL,
    web_name               TEXT NOT NULL,
    position_id            INTEGER NOT NULL,
    team_code              INTEGER NOT NULL,
    price                  NUMERIC NOT NULL,
    expected_points        NUMERIC NOT NULL,
    squad_role             TEXT NOT NULL,   -- 'starting' or 'bench'
    bench_order            INTEGER,         -- null for starting players
    is_captain             BOOLEAN NOT NULL DEFAULT false,
    is_vice_captain        BOOLEAN NOT NULL DEFAULT false,
    total_squad_cost       NUMERIC NOT NULL,
    total_expected_points  NUMERIC NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_squad_recommendations_gameweek
    ON optimizer.squad_recommendations (gameweek_id, generated_at);

/*
Chip-timing evaluation output. Populated by scripts/chip_strategy.py.
Only covers the visible prediction horizon (default 8 gameweeks), not the
full up-to-19-week half-season chip window -- these are provisional
best-current-guess rankings, not a locked schedule, and should be
re-evaluated regularly as the season reveals double/blank gameweeks.
*/
CREATE TABLE IF NOT EXISTS optimizer.chip_opportunities (
    id                 BIGSERIAL PRIMARY KEY,
    generated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    chip_name          TEXT NOT NULL,   -- 'wildcard', 'bench_boost', 'triple_captain', 'free_hit'
    gameweek_id        INTEGER,         -- null for wildcard (a squad-drift decision, not gameweek-specific)
    opportunity_value  NUMERIC NOT NULL,
    detail             TEXT
);

CREATE INDEX IF NOT EXISTS idx_chip_opportunities_generated
    ON optimizer.chip_opportunities (generated_at);
