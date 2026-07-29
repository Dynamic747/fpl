{#
    Positional-average per-90 rates, weighted by each player's own sample
    size (total_weight). Used as the shrinkage target for players with
    little or no data (int_player_form_shrunk).
#}

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
