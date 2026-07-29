select
    position_id,
    position_name,
    position_name_short,
    squad_select,
    squad_min_play,
    squad_max_play
from {{ ref('stg_fpl__positions') }}
