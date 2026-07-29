select
    h.entry_id,
    h.gameweek_id,
    h.points,
    h.total_points,
    h.gameweek_rank,
    h.overall_rank,
    h.bank,
    h.team_value,
    h.transfers_made,
    h.transfers_cost,
    h.points_on_bench,
    ps.active_chip
from {{ ref('stg_fpl__entry_gameweek_history') }} h
left join {{ ref('stg_fpl__entry_picks_summary') }} ps
    on h.entry_id = ps.entry_id and h.gameweek_id = ps.gameweek_id
