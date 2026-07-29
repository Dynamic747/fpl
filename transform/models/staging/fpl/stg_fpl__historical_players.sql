with latest_snapshot as (
    select distinct on (season)
        season,
        payload
    from {{ source('fpl_raw', 'historical_players_snapshot') }}
    order by season, fetched_at desc
),

unnested as (
    select
        season,
        jsonb_array_elements(payload) as player
    from latest_snapshot
)

select
    season,
    (player ->> 'id')::int                                                 as season_player_id,
    nullif(player ->> 'code', '')::int                                    as player_code,
    player ->> 'first_name'                                               as first_name,
    player ->> 'second_name'                                              as second_name,
    player ->> 'web_name'                                                 as web_name,
    nullif(player ->> 'team', '')::int                                    as season_team_id,
    nullif(player ->> 'element_type', '')::int                            as position_id,
    nullif(player ->> 'now_cost', '')::numeric / 10                        as end_of_season_price,
    nullif(player ->> 'total_points', '')::int                            as total_points,
    nullif(player ->> 'minutes', '')::int                                 as minutes,
    nullif(nullif(player ->> 'penalties_order', ''), 'None')::int                      as penalties_order,
    nullif(nullif(player ->> 'direct_freekicks_order', ''), 'None')::int               as direct_freekicks_order,
    nullif(nullif(player ->> 'corners_and_indirect_freekicks_order', ''), 'None')::int as corners_and_indirect_freekicks_order
from unnested
