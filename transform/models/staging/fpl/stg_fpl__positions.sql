with source as (
    select payload
    from {{ source('fpl_raw', 'bootstrap_static_snapshot') }}
    order by fetched_at desc
    limit 1
),

unnested as (
    select jsonb_array_elements(payload -> 'element_types') as position
    from source
)

select
    (position ->> 'id')::int             as position_id,
    position ->> 'singular_name'         as position_name,
    position ->> 'singular_name_short'   as position_name_short,
    (position ->> 'squad_select')::int   as squad_select,
    (position ->> 'squad_min_play')::int as squad_min_play,
    (position ->> 'squad_max_play')::int as squad_max_play
from unnested
