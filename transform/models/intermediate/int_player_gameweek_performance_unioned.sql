{#
    Unions the current season's live player-gameweek stats with 5 seasons of
    historical stats bulk-loaded from the vaastav GitHub archive.

    The two sources use different, season-specific player/team id spaces
    (FPL reassigns element ids every season), so both sides are resolved to
    the stable `player_code` / `team_code` identifiers before the union.
    Historical own-team is resolved by team name (verified identical between
    merged_gw.csv and that season's teams.csv) since it reflects the team a
    player was actually at that gameweek, not their end-of-season team.
#}

with current_season as (

    select
        '{{ var('current_season') }}'                as season,
        h.gameweek_id,
        p.player_code,
        p.web_name                                  as player_name,
        p.position_id,
        pt.team_code,
        ot.team_code                                as opponent_team_code,
        h.was_home,
        h.fixture_id,
        h.total_points,
        h.minutes,
        h.starts,
        h.goals_scored,
        h.assists,
        h.clean_sheets,
        h.goals_conceded,
        h.own_goals,
        h.penalties_missed,
        h.penalties_saved,
        h.yellow_cards,
        h.red_cards,
        h.saves,
        h.bonus,
        h.bps,
        h.influence,
        h.creativity,
        h.threat,
        h.ict_index,
        h.expected_goals,
        h.expected_assists,
        h.expected_goal_involvements,
        h.expected_goals_conceded,
        null::numeric                                as expected_points,
        h.price_at_gameweek,
        h.selected_by_count,
        h.transfers_in,
        h.transfers_out

    from {{ ref('stg_fpl__player_gameweek_history') }} h
    inner join {{ ref('stg_fpl__players') }} p on h.player_id = p.player_id
    left join {{ ref('stg_fpl__teams') }} pt on p.team_id = pt.team_id
    left join {{ ref('stg_fpl__teams') }} ot on h.opponent_team_id = ot.team_id

),

historical as (

    select
        g.season,
        g.gameweek_id,
        hp.player_code,
        g.player_name,
        hp.position_id,
        pt.team_code,
        ot.team_code                                 as opponent_team_code,
        g.was_home,
        g.fixture_id,
        g.total_points,
        g.minutes,
        g.starts,
        g.goals_scored,
        g.assists,
        g.clean_sheets,
        g.goals_conceded,
        g.own_goals,
        g.penalties_missed,
        g.penalties_saved,
        g.yellow_cards,
        g.red_cards,
        g.saves,
        g.bonus,
        g.bps,
        g.influence,
        g.creativity,
        g.threat,
        g.ict_index,
        g.expected_goals,
        g.expected_assists,
        g.expected_goal_involvements,
        g.expected_goals_conceded,
        g.expected_points,
        g.price_at_gameweek,
        g.selected_by_count,
        g.transfers_in,
        g.transfers_out

    from {{ ref('stg_fpl__historical_player_gameweek_stats') }} g
    inner join {{ ref('stg_fpl__historical_players') }} hp
        on g.season = hp.season and g.season_player_id = hp.season_player_id
    left join {{ ref('stg_fpl__historical_teams') }} pt
        on g.season = pt.season and g.team_name = pt.team_name
    left join {{ ref('stg_fpl__historical_teams') }} ot
        on g.season = ot.season and g.opponent_team_id = ot.season_team_id

)

select * from current_season
union all
select * from historical
