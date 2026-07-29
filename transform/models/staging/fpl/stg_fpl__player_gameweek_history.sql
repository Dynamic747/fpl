with latest_snapshot as (
    select distinct on (element_id)
        element_id,
        payload
    from {{ source('fpl_raw', 'element_summary_snapshot') }}
    order by element_id, fetched_at desc
),

unnested as (
    select
        element_id,
        jsonb_array_elements(payload -> 'history') as gw
    from latest_snapshot
)

select
    element_id                          as player_id,
    (gw ->> 'fixture')::int             as fixture_id,
    (gw ->> 'round')::int               as gameweek_id,
    (gw ->> 'opponent_team')::int       as opponent_team_id,
    (gw ->> 'was_home')::boolean        as was_home,
    (gw ->> 'total_points')::int        as total_points,
    (gw ->> 'minutes')::int             as minutes,
    (gw ->> 'starts')::int              as starts,
    (gw ->> 'goals_scored')::int        as goals_scored,
    (gw ->> 'assists')::int             as assists,
    (gw ->> 'clean_sheets')::int        as clean_sheets,
    (gw ->> 'goals_conceded')::int      as goals_conceded,
    (gw ->> 'own_goals')::int           as own_goals,
    (gw ->> 'penalties_missed')::int    as penalties_missed,
    (gw ->> 'penalties_saved')::int     as penalties_saved,
    (gw ->> 'yellow_cards')::int        as yellow_cards,
    (gw ->> 'red_cards')::int           as red_cards,
    (gw ->> 'saves')::int               as saves,
    (gw ->> 'bonus')::int               as bonus,
    (gw ->> 'bps')::int                 as bps,
    (gw ->> 'influence')::numeric       as influence,
    (gw ->> 'creativity')::numeric      as creativity,
    (gw ->> 'threat')::numeric          as threat,
    (gw ->> 'ict_index')::numeric       as ict_index,
    (gw ->> 'expected_goals')::numeric  as expected_goals,
    (gw ->> 'expected_assists')::numeric as expected_assists,
    (gw ->> 'expected_goal_involvements')::numeric as expected_goal_involvements,
    (gw ->> 'expected_goals_conceded')::numeric    as expected_goals_conceded,
    (gw ->> 'selected')::bigint         as selected_by_count,
    (gw ->> 'transfers_in')::int        as transfers_in,
    (gw ->> 'transfers_out')::int       as transfers_out,
    (gw ->> 'value')::numeric / 10      as price_at_gameweek
from unnested
