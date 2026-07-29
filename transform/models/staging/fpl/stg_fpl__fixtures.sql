with source as (
    select payload
    from {{ source('fpl_raw', 'fixtures_snapshot') }}
    order by fetched_at desc
    limit 1
),

unnested as (
    select jsonb_array_elements(payload) as fixture
    from source
)

select
    (fixture ->> 'id')::int                       as fixture_id,
    (fixture ->> 'event')::int                    as gameweek_id,
    (fixture ->> 'team_h')::int                   as home_team_id,
    (fixture ->> 'team_a')::int                   as away_team_id,
    (fixture ->> 'team_h_difficulty')::int        as home_team_difficulty,
    (fixture ->> 'team_a_difficulty')::int        as away_team_difficulty,
    (fixture ->> 'team_h_score')::int             as home_team_score,
    (fixture ->> 'team_a_score')::int             as away_team_score,
    (fixture ->> 'kickoff_time')::timestamptz     as kickoff_time,
    (fixture ->> 'started')::boolean              as is_started,
    (fixture ->> 'finished')::boolean             as is_finished,
    (fixture ->> 'finished_provisional')::boolean as is_finished_provisional
from unnested
