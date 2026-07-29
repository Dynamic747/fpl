{#
    Recency-weighted per-90 rate stats for every player, blending current
    season with up to 5 historical seasons. Weight decays geometrically the
    further back a season is (0.55 per season back), so this automatically
    leans on current-season form once gameweeks are played, and falls back
    to last season + career history before a ball is kicked this season
    (e.g. for GW1 team selection) — no separate cold-start logic needed.

    total_weight also doubles as a confidence signal: a player with many
    weighted gameweeks of data should be trusted more than one with few,
    which fct_player_expected_points uses to shrink low-sample players
    toward a positional baseline.
#}

with base as (

    select
        player_code,
        left('{{ var("current_season") }}', 4)::int - left(season, 4)::int as seasons_back,
        minutes,
        starts,
        total_points,
        goals_scored,
        assists,
        clean_sheets,
        goals_conceded,
        own_goals,
        penalties_missed,
        penalties_saved,
        yellow_cards,
        red_cards,
        saves,
        bonus
    from {{ ref('fct_player_gameweek_performance') }}

),

weighted as (

    select
        *,
        power(0.55, greatest(seasons_back, 0)) as recency_weight
    from base

),

aggregated as (

    select
        player_code,
        sum(recency_weight)                     as total_weight,
        count(*)                                as gameweek_rows,
        sum(minutes * recency_weight)           as weighted_minutes,
        sum(starts * recency_weight)            as weighted_starts,
        sum(total_points * recency_weight)      as weighted_points,
        sum(goals_scored * recency_weight)      as weighted_goals,
        sum(assists * recency_weight)           as weighted_assists,
        sum(clean_sheets * recency_weight)      as weighted_clean_sheets,
        sum(goals_conceded * recency_weight)    as weighted_goals_conceded,
        sum(own_goals * recency_weight)         as weighted_own_goals,
        sum(penalties_missed * recency_weight)  as weighted_penalties_missed,
        sum(penalties_saved * recency_weight)   as weighted_penalties_saved,
        sum(yellow_cards * recency_weight)      as weighted_yellow_cards,
        sum(red_cards * recency_weight)         as weighted_red_cards,
        sum(saves * recency_weight)             as weighted_saves,
        sum(bonus * recency_weight)             as weighted_bonus,
        bool_or(seasons_back = 0 and minutes > 0) as has_current_season_minutes
    from weighted
    group by player_code

)

select
    player_code,
    total_weight,
    gameweek_rows,
    has_current_season_minutes,
    weighted_starts / nullif(total_weight, 0)                   as start_rate,
    weighted_points / nullif(weighted_minutes, 0) * 90          as points_per_90,
    weighted_goals / nullif(weighted_minutes, 0) * 90           as goals_per_90,
    weighted_assists / nullif(weighted_minutes, 0) * 90         as assists_per_90,
    weighted_clean_sheets / nullif(weighted_starts, 0)          as clean_sheet_rate_per_start,
    weighted_goals_conceded / nullif(weighted_minutes, 0) * 90  as goals_conceded_per_90,
    weighted_own_goals / nullif(weighted_minutes, 0) * 90       as own_goals_per_90,
    weighted_penalties_missed / nullif(weighted_minutes, 0) * 90 as penalties_missed_per_90,
    weighted_penalties_saved / nullif(weighted_minutes, 0) * 90  as penalties_saved_per_90,
    weighted_yellow_cards / nullif(weighted_minutes, 0) * 90    as yellow_cards_per_90,
    weighted_red_cards / nullif(weighted_minutes, 0) * 90       as red_cards_per_90,
    weighted_saves / nullif(weighted_minutes, 0) * 90           as saves_per_90,
    weighted_bonus / nullif(weighted_minutes, 0) * 90           as bonus_per_90
from aggregated
