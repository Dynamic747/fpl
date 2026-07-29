select
    t.entry_id,
    t.gameweek_id,
    pin.player_code  as player_in_code,
    t.player_in_cost,
    pout.player_code as player_out_code,
    t.player_out_cost,
    t.transferred_at
from {{ ref('stg_fpl__entry_transfers') }} t
left join {{ ref('stg_fpl__players') }} pin on t.player_in_id = pin.player_id
left join {{ ref('stg_fpl__players') }} pout on t.player_out_id = pout.player_id
