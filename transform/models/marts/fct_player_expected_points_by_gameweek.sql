{#
    Same formula as fct_player_expected_points, but for the next
    {{ var('prediction_horizon_gameweeks') }} gameweeks instead of just the
    next one. A player's own rate stats (int_player_form_shrunk) are held
    fixed across the horizon — only the opponent/fixture-difficulty
    multiplier changes per gameweek. Used for season-aware initial squad
    selection (fct_player_expected_points_horizon) rather than single-week
    decisions like captaincy, which should use fct_player_expected_points.
#}

with target_gameweeks as (

    select
        gameweek_id,
        row_number() over (order by gameweek_id) - 1 as weeks_ahead
    from {{ ref('dim_gameweeks') }}
    where season = '{{ var("current_season") }}'
      and gameweek_id >= (
          select gameweek_id from {{ ref('dim_gameweeks') }}
          where season = '{{ var("current_season") }}' and is_next = true
          limit 1
      )
    order by gameweek_id
    limit {{ var('prediction_horizon_gameweeks') }}

),

league_averages as (

    select
        avg(strength_attack_home)  as avg_attack_home,
        avg(strength_attack_away)  as avg_attack_away,
        avg(strength_defence_home) as avg_defence_home,
        avg(strength_defence_away) as avg_defence_away
    from {{ ref('dim_teams') }}
    where is_in_current_season = true

),

player_fixtures as (

    -- LEFT JOIN so a blank gameweek still gets exactly one row per player
    -- (fixture_id null) rather than disappearing; a double gameweek gets
    -- two rows, one per fixture.
    select
        pf.player_code,
        tg.gameweek_id,
        f.fixture_id,
        case when f.home_team_code = pf.current_team_code then f.away_team_code else f.home_team_code end as opponent_team_code,
        (f.home_team_code = pf.current_team_code) as is_home
    from {{ ref('int_player_form_shrunk') }} pf
    cross join target_gameweeks tg
    left join {{ ref('fct_fixtures') }} f
        on f.gameweek_id = tg.gameweek_id
       and (f.home_team_code = pf.current_team_code or f.away_team_code = pf.current_team_code)

),

fixture_points as (

    select
        pfx.gameweek_id,
        pfx.fixture_id,
        pf.availability_factor * (pf.start_rate * 90 + (1 - pf.start_rate) * 15) as expected_minutes,

        case when pfx.is_home
             then la.avg_defence_away / nullif(ot.strength_defence_away, 0)
             else la.avg_defence_home / nullif(ot.strength_defence_home, 0)
        end as attack_multiplier,

        case when pfx.is_home
             then la.avg_attack_away / nullif(ot.strength_attack_away, 0)
             else la.avg_attack_home / nullif(ot.strength_attack_home, 0)
        end as defence_multiplier,

        pf.*,
        sr.goal_points,
        sr.assist_points,
        sr.clean_sheet_points,
        sr.points_per_60_min_start,
        sr.goals_conceded_penalty_per_2,
        sr.yellow_card_points,
        sr.red_card_points,
        sr.own_goal_points,
        sr.penalty_miss_points,
        sr.penalty_save_points,
        sr.save_points_per_3

    from player_fixtures pfx
    inner join {{ ref('int_player_form_shrunk') }} pf on pfx.player_code = pf.player_code
    left join {{ ref('dim_teams') }} ot on pfx.opponent_team_code = ot.team_code
    inner join {{ ref('scoring_rules') }} sr on pf.position_id = sr.position_id
    cross join league_averages la

),

fixture_expected_points as (

    select
        player_code,
        gameweek_id,
        fixture_id,
        case when fixture_id is null then 0 else

            (expected_minutes / 90.0) * points_per_60_min_start

            + (expected_minutes / 90.0) * goals_per_90 * attack_multiplier * goal_points

            + (expected_minutes / 90.0) * assists_per_90 * attack_multiplier * assist_points

            + availability_factor * start_rate * clean_sheet_rate_per_start * defence_multiplier * clean_sheet_points

            + (expected_minutes / 90.0) * (goals_conceded_per_90 / nullif(defence_multiplier, 0)) / 2.0
                * goals_conceded_penalty_per_2

            + (expected_minutes / 90.0) * bonus_per_90

            + (expected_minutes / 90.0) * yellow_cards_per_90 * yellow_card_points
            + (expected_minutes / 90.0) * red_cards_per_90 * red_card_points

            + (expected_minutes / 90.0) * own_goals_per_90 * own_goal_points
            + (expected_minutes / 90.0) * penalties_missed_per_90 * penalty_miss_points
            + (expected_minutes / 90.0) * penalties_saved_per_90 * penalty_save_points

            + (expected_minutes / 90.0) * saves_per_90 / 3.0 * save_points_per_3

        end as points

    from fixture_points

)

select
    pf.player_code,
    pf.web_name,
    pf.position_id,
    pf.current_team_code,
    pf.current_price,
    tg.gameweek_id,
    tg.weeks_ahead,
    count(fep.fixture_id)        as fixture_count,
    coalesce(sum(fep.points), 0) as expected_points
from {{ ref('int_player_form_shrunk') }} pf
cross join target_gameweeks tg
left join fixture_expected_points fep
    on pf.player_code = fep.player_code and tg.gameweek_id = fep.gameweek_id
group by
    pf.player_code, pf.web_name, pf.position_id, pf.current_team_code,
    pf.current_price, tg.gameweek_id, tg.weeks_ahead
order by pf.player_code, tg.gameweek_id
