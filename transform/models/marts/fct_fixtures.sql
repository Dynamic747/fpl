{#
    Current season only. Historical fixtures weren't bulk-loaded since the
    historical fixture context a player faced is already captured directly
    on fct_player_gameweek_performance (opponent_team_code, was_home).
#}

select
    f.fixture_id,
    '{{ var('current_season') }}' as season,
    f.gameweek_id,
    ht.team_code                as home_team_code,
    at.team_code                as away_team_code,
    f.home_team_difficulty,
    f.away_team_difficulty,
    f.home_team_score,
    f.away_team_score,
    f.kickoff_time,
    f.is_started,
    f.is_finished,
    f.is_finished_provisional
from {{ ref('stg_fpl__fixtures') }} f
left join {{ ref('stg_fpl__teams') }} ht on f.home_team_id = ht.team_id
left join {{ ref('stg_fpl__teams') }} at on f.away_team_id = at.team_id
