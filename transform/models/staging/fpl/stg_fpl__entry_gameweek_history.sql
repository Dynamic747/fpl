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
        jsonb_array_elements(payload -> 'current') as gw
    from latest_snapshot
)

select
    entry_id,
    (gw ->> 'event')::int                as gameweek_id,
    (gw ->> 'points')::int               as points,
    (gw ->> 'total_points')::int         as total_points,
    (gw ->> 'rank')::bigint              as gameweek_rank,
    (gw ->> 'overall_rank')::bigint      as overall_rank,
    (gw ->> 'bank')::numeric / 10        as bank,
    (gw ->> 'value')::numeric / 10       as team_value,
    (gw ->> 'event_transfers')::int      as transfers_made,
    (gw ->> 'event_transfers_cost')::int as transfers_cost,
    (gw ->> 'points_on_bench')::int      as points_on_bench
from unnested
