{#
    One row per current-squad player: recency-weighted rates
    (int_player_recent_form) shrunk toward the positional baseline in
    proportion to sample size, plus an availability_factor from injury/
    suspension status. This is the shared input for any expected-points
    model regardless of which gameweek(s) it targets — a player's
    underlying rate stats don't change per fixture, only the opponent does.

    Shrinkage: total_weight is a recency-weighted *gameweek* count (not
    minutes); ~10 weighted gameweeks is treated as "as much trust as the
    positional prior" — a player with zero data gets pure baseline, an
    ever-present player (weight 40-80+) gets mostly their own rate.
#}

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
inner join {{ ref('int_positional_baseline') }} pb on d.position_id = pb.position_id
where d.is_in_current_season = true
