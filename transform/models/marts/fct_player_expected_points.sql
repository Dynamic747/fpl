{#
    Expected points for each current-squad player for the NEXT unplayed
    gameweek (dim_gameweeks.is_next). Handles blank gameweeks (0 fixtures
    that week for a player's team -> 0 expected points) and double
    gameweeks (2 fixtures -> points summed across both) via a LEFT JOIN to
    fixtures rather than assuming exactly one match per player.

    Approach: recency-weighted historical/current-season per-90 rates
    (int_player_recent_form), shrunk toward a positional baseline in
    proportion to sample size (so a brand-new signing, or a Coventry/Hull
    player with zero top-flight history, gets essentially the positional
    average rather than a wild guess), then scaled by expected minutes and
    a fixture-difficulty multiplier derived from each team's home/away
    attack/defence strength ratings (dim_teams) relative to the league
    average.

    Known simplifications (v1): appearance points are interpolated
    continuously by expected-minutes fraction rather than FPL's actual 1pt
    (<60min) / 2pt (60min+) step function; bonus points are carried
    forward at the player's historical bonus-per-90 rate rather than
    modeled from BPS components; the 2024-25+ "defensive contribution"
    points rule isn't modeled at all (no raw tackles/clearances/
    interceptions data has been ingested); no explicit rotation/team-news
    signal beyond chance_of_playing_next_round and historical start_rate.
#}

with target_gameweek as (

    select gameweek_id
    from {{ ref('dim_gameweeks') }}
    where season = '{{ var("current_season") }}' and is_next = true
    limit 1

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

positional_baseline as (

    select
        d.position_id,
        sum(coalesce(r.goals_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)               as goals_per_90,
        sum(coalesce(r.assists_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)              as assists_per_90,
        sum(coalesce(r.clean_sheet_rate_per_start, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)  as clean_sheet_rate_per_start,
        sum(coalesce(r.goals_conceded_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)       as goals_conceded_per_90,
        sum(coalesce(r.own_goals_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)            as own_goals_per_90,
        sum(coalesce(r.penalties_missed_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)     as penalties_missed_per_90,
        sum(coalesce(r.penalties_saved_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)      as penalties_saved_per_90,
        sum(coalesce(r.yellow_cards_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)         as yellow_cards_per_90,
        sum(coalesce(r.red_cards_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)            as red_cards_per_90,
        sum(coalesce(r.saves_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)                as saves_per_90,
        sum(coalesce(r.bonus_per_90, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)                as bonus_per_90,
        sum(coalesce(r.start_rate, 0) * r.total_weight) / nullif(sum(r.total_weight), 0)                  as start_rate
    from {{ ref('int_player_recent_form') }} r
    inner join {{ ref('dim_players') }} d on r.player_code = d.player_code
    group by d.position_id

),

player_form as (

    -- Shrinkage: blend the player's own recency-weighted rate with the
    -- positional baseline, weighted by sample size (confidence_weight).
    -- total_weight is a recency-weighted *gameweek* count (not minutes);
    -- ~10 weighted gameweeks is treated as "as much trust as the
    -- positional prior" — a player with zero data gets pure baseline, an
    -- ever-present player (weight 40-80+) gets mostly their own rate.
    select
        d.player_code,
        d.web_name,
        d.position_id,
        d.current_team_code,
        d.current_price,
        d.status,
        d.chance_of_playing_next_round,
        -- if status isn't 'a' (available) and no percentage is given, treat as
        -- 0% rather than defaulting to fully fit — a flagged-unavailable
        -- player with no percentage should not be assumed to play
        case when d.status = 'a' then coalesce(d.chance_of_playing_next_round, 100) / 100.0
             else coalesce(d.chance_of_playing_next_round, 0) / 100.0
        end as availability_factor,
        coalesce(r.total_weight, 0) / 10.0 as confidence_weight,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.start_rate, 0) + pb.start_rate)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as start_rate,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.goals_per_90, 0) + pb.goals_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as goals_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.assists_per_90, 0) + pb.assists_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as assists_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.clean_sheet_rate_per_start, 0) + pb.clean_sheet_rate_per_start)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as clean_sheet_rate_per_start,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.goals_conceded_per_90, 0) + pb.goals_conceded_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as goals_conceded_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.own_goals_per_90, 0) + pb.own_goals_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as own_goals_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.penalties_missed_per_90, 0) + pb.penalties_missed_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as penalties_missed_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.penalties_saved_per_90, 0) + pb.penalties_saved_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as penalties_saved_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.yellow_cards_per_90, 0) + pb.yellow_cards_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as yellow_cards_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.red_cards_per_90, 0) + pb.red_cards_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as red_cards_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.saves_per_90, 0) + pb.saves_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as saves_per_90,
        (coalesce(r.total_weight, 0) / 10.0 * coalesce(r.bonus_per_90, 0) + pb.bonus_per_90)
            / (coalesce(r.total_weight, 0) / 10.0 + 1.0) as bonus_per_90
    from {{ ref('dim_players') }} d
    left join {{ ref('int_player_recent_form') }} r on d.player_code = r.player_code
    inner join positional_baseline pb on d.position_id = pb.position_id
    where d.is_in_current_season = true

),

player_fixtures as (

    -- LEFT JOIN so blank-gameweek players still get exactly one row
    -- (fixture_id null) rather than disappearing; double-gameweek players
    -- get two rows, one per fixture.
    select
        pf.player_code,
        f.fixture_id,
        case when f.home_team_code = pf.current_team_code then f.away_team_code else f.home_team_code end as opponent_team_code,
        (f.home_team_code = pf.current_team_code) as is_home
    from player_form pf
    cross join target_gameweek tg
    left join {{ ref('fct_fixtures') }} f
        on f.gameweek_id = tg.gameweek_id
       and (f.home_team_code = pf.current_team_code or f.away_team_code = pf.current_team_code)

),

fixture_points as (

    select
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
    inner join player_form pf on pfx.player_code = pf.player_code
    left join {{ ref('dim_teams') }} ot on pfx.opponent_team_code = ot.team_code
    inner join {{ ref('scoring_rules') }} sr on pf.position_id = sr.position_id
    cross join league_averages la

),

fixture_expected_points as (

    select
        player_code,
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
    pf.status,
    pf.chance_of_playing_next_round,
    pf.confidence_weight,
    tg.gameweek_id,
    count(fep.fixture_id)              as fixture_count,
    coalesce(sum(fep.points), 0)       as expected_points
from player_form pf
cross join target_gameweek tg
left join fixture_expected_points fep on pf.player_code = fep.player_code
group by
    pf.player_code, pf.web_name, pf.position_id, pf.current_team_code,
    pf.current_price, pf.status, pf.chance_of_playing_next_round,
    pf.confidence_weight, tg.gameweek_id
order by expected_points desc
