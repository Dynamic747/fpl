with latest_snapshot as (
    select distinct on (entry_id)
        entry_id,
        payload
    from {{ source('fpl_raw', 'entry_history_snapshot') }}
    order by entry_id, fetched_at desc
),

unnested as (
    select
        entry_id,
        jsonb_array_elements(payload -> 'chips') as chip
    from latest_snapshot
)

select
    entry_id,
    chip ->> 'name'                as chip_name,
    (chip ->> 'event')::int        as gameweek_id,
    (chip ->> 'time')::timestamptz as played_at
from unnested
