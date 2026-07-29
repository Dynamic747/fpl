with latest_snapshot as (
    select distinct on (entry_id)
        entry_id,
        payload
    from {{ source('fpl_raw', 'entry_transfers_snapshot') }}
    order by entry_id, fetched_at desc
),

unnested as (
    select
        entry_id,
        jsonb_array_elements(payload) as transfer
    from latest_snapshot
)

select
    entry_id,
    (transfer ->> 'event')::int                      as gameweek_id,
    (transfer ->> 'element_in')::int                 as player_in_id,
    (transfer ->> 'element_in_cost')::numeric / 10   as player_in_cost,
    (transfer ->> 'element_out')::int                as player_out_id,
    (transfer ->> 'element_out_cost')::numeric / 10  as player_out_cost,
    (transfer ->> 'time')::timestamptz               as transferred_at
from unnested
