with latest_snapshot as (
    select distinct on (season)
        season,
        payload
    from {{ source('fpl_raw', 'historical_teams_snapshot') }}
    order by season, fetched_at desc
),

unnested as (
    select
        season,
        jsonb_array_elements(payload) as team
    from latest_snapshot
)

select
    season,
    (team ->> 'id')::int   as season_team_id,
    (team ->> 'code')::int as team_code,
    team ->> 'name'        as team_name,
    team ->> 'short_name'  as team_short_name
from unnested
