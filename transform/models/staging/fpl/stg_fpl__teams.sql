with source as (
    select payload
    from {{ source('fpl_raw', 'bootstrap_static_snapshot') }}
    order by fetched_at desc
    limit 1
),

unnested as (
    select jsonb_array_elements(payload -> 'teams') as team
    from source
)

select
    (team ->> 'id')::int                    as team_id,
    (team ->> 'code')::int                  as team_code,
    team ->> 'name'                         as team_name,
    team ->> 'short_name'                   as team_short_name,
    (team ->> 'strength')::int              as strength,
    (team ->> 'strength_overall_home')::int as strength_overall_home,
    (team ->> 'strength_overall_away')::int as strength_overall_away,
    (team ->> 'strength_attack_home')::int  as strength_attack_home,
    (team ->> 'strength_attack_away')::int  as strength_attack_away,
    (team ->> 'strength_defence_home')::int as strength_defence_home,
    (team ->> 'strength_defence_away')::int as strength_defence_away,
    (team ->> 'played')::int                as played,
    (team ->> 'position')::int              as league_position,
    (team ->> 'points')::int                as points
from unnested
