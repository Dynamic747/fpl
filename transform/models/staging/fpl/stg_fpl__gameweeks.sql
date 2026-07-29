with source as (
    select payload
    from {{ source('fpl_raw', 'bootstrap_static_snapshot') }}
    order by fetched_at desc
    limit 1
),

unnested as (
    select jsonb_array_elements(payload -> 'events') as gameweek
    from source
)

select
    (gameweek ->> 'id')::int                    as gameweek_id,
    gameweek ->> 'name'                         as gameweek_name,
    (gameweek ->> 'deadline_time')::timestamptz as deadline_time,
    (gameweek ->> 'finished')::boolean          as is_finished,
    (gameweek ->> 'is_current')::boolean        as is_current,
    (gameweek ->> 'is_next')::boolean           as is_next,
    (gameweek ->> 'average_entry_score')::int   as average_entry_score,
    (gameweek ->> 'highest_score')::int         as highest_score
from unnested
