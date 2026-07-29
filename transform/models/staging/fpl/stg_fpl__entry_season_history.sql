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
        jsonb_array_elements(payload -> 'past') as season
    from latest_snapshot
)

select
    entry_id,
    season ->> 'season_name'         as season_name,
    (season ->> 'total_points')::int as total_points,
    (season ->> 'rank')::bigint      as season_rank
from unnested
