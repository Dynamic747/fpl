{#
    Conformed across seasons: many historical players are no longer in the
    Premier League, so a current-squad-only dimension would leave historical
    fact rows with orphaned foreign keys. current_players wins on any
    player_code overlap; players no longer in this season get null
    price/form/status.
#}

with current_players as (

    select
        p.player_code,
        p.player_id                            as current_player_id,
        p.first_name,
        p.second_name,
        p.web_name,
        t.team_code                            as current_team_code,
        p.position_id,
        p.price                                as current_price,
        p.total_points                         as current_season_total_points,
        p.form,
        p.selected_by_percent,
        p.status,
        p.news,
        p.chance_of_playing_next_round,
        p.chance_of_playing_this_round,
        p.penalties_order,
        p.direct_freekicks_order,
        p.corners_and_indirect_freekicks_order,
        true                                    as is_in_current_season
    from {{ ref('stg_fpl__players') }} p
    left join {{ ref('stg_fpl__teams') }} t on p.team_id = t.team_id

),

historical_only_players as (

    select distinct on (hp.player_code)
        hp.player_code,
        null::int    as current_player_id,
        hp.first_name,
        hp.second_name,
        hp.web_name,
        null::int    as current_team_code,
        hp.position_id,
        null::numeric as current_price,
        null::int    as current_season_total_points,
        null::numeric as form,
        null::numeric as selected_by_percent,
        null::text   as status,
        null::text   as news,
        null::int    as chance_of_playing_next_round,
        null::int    as chance_of_playing_this_round,
        hp.penalties_order,
        hp.direct_freekicks_order,
        hp.corners_and_indirect_freekicks_order,
        false         as is_in_current_season
    from {{ ref('stg_fpl__historical_players') }} hp
    where hp.player_code is not null
      and not exists (
          select 1 from current_players cp where cp.player_code = hp.player_code
      )
    order by hp.player_code, hp.season desc

)

select * from current_players
union all
select * from historical_only_players
