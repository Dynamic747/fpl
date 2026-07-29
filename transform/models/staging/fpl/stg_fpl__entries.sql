with latest_snapshot as (
    select distinct on (entry_id)
        entry_id,
        fetched_at,
        payload
    from {{ source('fpl_raw', 'entry_snapshot') }}
    order by entry_id, fetched_at desc
)

select
    entry_id,
    payload ->> 'player_first_name'              as manager_first_name,
    payload ->> 'player_last_name'               as manager_last_name,
    payload ->> 'name'                           as team_name,
    (payload ->> 'favourite_team')::int          as favourite_team_id,
    (payload ->> 'summary_overall_points')::int  as overall_points,
    (payload ->> 'summary_overall_rank')::bigint as overall_rank,
    (payload ->> 'current_event')::int           as current_event,
    fetched_at
from latest_snapshot
