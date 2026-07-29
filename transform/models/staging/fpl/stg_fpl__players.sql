with source as (
    select payload
    from {{ source('fpl_raw', 'bootstrap_static_snapshot') }}
    order by fetched_at desc
    limit 1
),

unnested as (
    select jsonb_array_elements(payload -> 'elements') as player
    from source
)

select
    (player ->> 'id')::int                            as player_id,
    (player ->> 'code')::int                          as player_code,
    player ->> 'first_name'                           as first_name,
    player ->> 'second_name'                          as second_name,
    player ->> 'web_name'                             as web_name,
    (player ->> 'team')::int                          as team_id,
    (player ->> 'element_type')::int                  as position_id,
    (player ->> 'now_cost')::numeric / 10              as price,
    (player ->> 'total_points')::int                  as total_points,
    (player ->> 'points_per_game')::numeric           as points_per_game,
    (player ->> 'form')::numeric                      as form,
    (player ->> 'selected_by_percent')::numeric       as selected_by_percent,
    player ->> 'status'                               as status,
    nullif(player ->> 'news', '')                     as news,
    (player ->> 'chance_of_playing_next_round')::int  as chance_of_playing_next_round,
    (player ->> 'chance_of_playing_this_round')::int  as chance_of_playing_this_round,
    (player ->> 'minutes')::int                       as minutes,
    (player ->> 'goals_scored')::int                  as goals_scored,
    (player ->> 'assists')::int                       as assists,
    (player ->> 'clean_sheets')::int                  as clean_sheets,
    (player ->> 'goals_conceded')::int                as goals_conceded,
    (player ->> 'own_goals')::int                     as own_goals,
    (player ->> 'penalties_saved')::int               as penalties_saved,
    (player ->> 'penalties_missed')::int              as penalties_missed,
    (player ->> 'yellow_cards')::int                  as yellow_cards,
    (player ->> 'red_cards')::int                     as red_cards,
    (player ->> 'saves')::int                         as saves,
    (player ->> 'bonus')::int                         as bonus,
    (player ->> 'bps')::int                           as bps,
    (player ->> 'influence')::numeric                 as influence,
    (player ->> 'creativity')::numeric                as creativity,
    (player ->> 'threat')::numeric                    as threat,
    (player ->> 'ict_index')::numeric                 as ict_index,
    (player ->> 'starts')::int                        as starts,
    (player ->> 'expected_goals')::numeric            as expected_goals,
    (player ->> 'expected_assists')::numeric          as expected_assists,
    (player ->> 'expected_goal_involvements')::numeric as expected_goal_involvements,
    (player ->> 'expected_goals_conceded')::numeric   as expected_goals_conceded,
    (player ->> 'transfers_in_event')::int            as transfers_in_event,
    (player ->> 'transfers_out_event')::int           as transfers_out_event,
    (player ->> 'penalties_order')::int               as penalties_order,
    (player ->> 'direct_freekicks_order')::int        as direct_freekicks_order,
    (player ->> 'corners_and_indirect_freekicks_order')::int as corners_and_indirect_freekicks_order
from unnested
