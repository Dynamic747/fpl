select
    ep.entry_id,
    ep.gameweek_id,
    p.player_code,
    ep.squad_position,
    ep.multiplier,
    ep.is_captain,
    ep.is_vice_captain
from {{ ref('stg_fpl__entry_picks') }} ep
left join {{ ref('stg_fpl__players') }} p on ep.player_id = p.player_id
