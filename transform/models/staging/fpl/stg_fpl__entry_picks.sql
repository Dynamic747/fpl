with latest_snapshot as (
    select distinct on (entry_id, event_id)
        entry_id,
        event_id,
        payload
    from {{ source('fpl_raw', 'entry_picks_snapshot') }}
    order by entry_id, event_id, fetched_at desc
),

unnested as (
    select
        entry_id,
        event_id,
        jsonb_array_elements(payload -> 'picks') as pick
    from latest_snapshot
)

select
    entry_id,
    event_id                              as gameweek_id,
    (pick ->> 'element')::int             as player_id,
    (pick ->> 'position')::int            as squad_position,
    (pick ->> 'multiplier')::int          as multiplier,
    (pick ->> 'is_captain')::boolean      as is_captain,
    (pick ->> 'is_vice_captain')::boolean as is_vice_captain
from unnested
