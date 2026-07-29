{#
    Current season has full gameweek metadata from the live API. Historical
    seasons only have the gameweek number itself (from merged_gw.csv's
    `round` column) — no deadline/finished-flag metadata was bulk-loaded,
    since that's not needed for training data, only for live-season logic.
#}

with current_season as (

    select
        '{{ var('current_season') }}' as season,
        gameweek_id,
        gameweek_name,
        deadline_time,
        is_finished,
        is_current,
        is_next,
        average_entry_score,
        highest_score
    from {{ ref('stg_fpl__gameweeks') }}

),

historical as (

    select distinct
        season,
        gameweek_id,
        'Gameweek ' || gameweek_id as gameweek_name,
        null::timestamptz         as deadline_time,
        true                       as is_finished,
        false                      as is_current,
        false                      as is_next,
        null::int                 as average_entry_score,
        null::int                 as highest_score
    from {{ ref('stg_fpl__historical_player_gameweek_stats') }}
    where gameweek_id is not null

)

select * from current_season
union all
select * from historical
