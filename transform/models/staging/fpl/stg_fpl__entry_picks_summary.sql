with latest_snapshot as (
    select distinct on (entry_id, event_id)
        entry_id,
        event_id,
        payload
    from {{ source('fpl_raw', 'entry_picks_snapshot') }}
    order by entry_id, event_id, fetched_at desc
)

select
    entry_id,
    event_id                                                      as gameweek_id,
    payload ->> 'active_chip'                                     as active_chip,
    (payload -> 'entry_history' ->> 'bank')::numeric / 10             as bank,
    (payload -> 'entry_history' ->> 'value')::numeric / 10            as team_value,
    (payload -> 'entry_history' ->> 'event_transfers')::int           as transfers_made,
    (payload -> 'entry_history' ->> 'event_transfers_cost')::int      as transfers_cost,
    (payload -> 'entry_history' ->> 'points_on_bench')::int           as points_on_bench,
    (payload -> 'entry_history' ->> 'points')::int                    as gameweek_points,
    (payload -> 'entry_history' ->> 'total_points')::int              as total_points,
    (payload -> 'entry_history' ->> 'overall_rank')::bigint           as overall_rank
from latest_snapshot
