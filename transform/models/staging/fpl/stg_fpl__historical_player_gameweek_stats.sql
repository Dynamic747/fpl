with latest_snapshot as (
    select distinct on (season)
        season,
        payload
    from {{ source('fpl_raw', 'historical_gw_stats_snapshot') }}
    order by season, fetched_at desc
),

unnested as (
    select
        season,
        jsonb_array_elements(payload) as gw
    from latest_snapshot
)

select
    season,
    (gw ->> 'element')::int                                            as season_player_id,
    gw ->> 'name'                                                      as player_name,
    gw ->> 'position'                                                  as position_name,
    gw ->> 'team'                                                      as team_name,
    nullif(gw ->> 'round', '')::int                                    as gameweek_id,
    nullif(gw ->> 'fixture', '')::int                                  as fixture_id,
    nullif(gw ->> 'opponent_team', '')::int                            as opponent_team_id,
    nullif(gw ->> 'was_home', '')::boolean                             as was_home,
    nullif(gw ->> 'kickoff_time', '')::timestamptz                     as kickoff_time,
    nullif(gw ->> 'total_points', '')::int                             as total_points,
    nullif(gw ->> 'minutes', '')::int                                  as minutes,
    nullif(gw ->> 'starts', '')::int                                   as starts,
    nullif(gw ->> 'goals_scored', '')::int                             as goals_scored,
    nullif(gw ->> 'assists', '')::int                                  as assists,
    nullif(gw ->> 'clean_sheets', '')::int                             as clean_sheets,
    nullif(gw ->> 'goals_conceded', '')::int                           as goals_conceded,
    nullif(gw ->> 'own_goals', '')::int                                as own_goals,
    nullif(gw ->> 'penalties_missed', '')::int                        as penalties_missed,
    nullif(gw ->> 'penalties_saved', '')::int                         as penalties_saved,
    nullif(gw ->> 'yellow_cards', '')::int                            as yellow_cards,
    nullif(gw ->> 'red_cards', '')::int                               as red_cards,
    nullif(gw ->> 'saves', '')::int                                   as saves,
    nullif(gw ->> 'bonus', '')::int                                   as bonus,
    nullif(gw ->> 'bps', '')::int                                     as bps,
    nullif(gw ->> 'influence', '')::numeric                           as influence,
    nullif(gw ->> 'creativity', '')::numeric                          as creativity,
    nullif(gw ->> 'threat', '')::numeric                               as threat,
    nullif(gw ->> 'ict_index', '')::numeric                            as ict_index,
    nullif(gw ->> 'expected_goals', '')::numeric                       as expected_goals,
    nullif(gw ->> 'expected_assists', '')::numeric                     as expected_assists,
    nullif(gw ->> 'expected_goal_involvements', '')::numeric           as expected_goal_involvements,
    nullif(gw ->> 'expected_goals_conceded', '')::numeric              as expected_goals_conceded,
    nullif(gw ->> 'xP', '')::numeric                                   as expected_points,
    nullif(gw ->> 'value', '')::numeric / 10                           as price_at_gameweek,
    nullif(gw ->> 'selected', '')::bigint                              as selected_by_count,
    nullif(gw ->> 'transfers_in', '')::int                             as transfers_in,
    nullif(gw ->> 'transfers_out', '')::int                            as transfers_out,
    nullif(gw ->> 'transfers_balance', '')::int                        as transfers_balance
from unnested
