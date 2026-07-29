{#
    Conformed across seasons: team rosters change every season (promotion/
    relegation), so a current-only dimension would leave historical fact
    rows (referencing relegated clubs) with orphaned foreign keys.
    current_teams wins on any team_code overlap; teams no longer in the
    Premier League get null strength/current attributes.
#}

with current_teams as (

    select
        team_code,
        team_id  as current_team_id,
        team_name,
        team_short_name,
        strength,
        strength_overall_home,
        strength_overall_away,
        strength_attack_home,
        strength_attack_away,
        strength_defence_home,
        strength_defence_away,
        league_position,
        points,
        true     as is_in_current_season
    from {{ ref('stg_fpl__teams') }}

),

historical_only_teams as (

    select distinct on (ht.team_code)
        ht.team_code,
        null::int as current_team_id,
        ht.team_name,
        ht.team_short_name,
        null::int as strength,
        null::int as strength_overall_home,
        null::int as strength_overall_away,
        null::int as strength_attack_home,
        null::int as strength_attack_away,
        null::int as strength_defence_home,
        null::int as strength_defence_away,
        null::int as league_position,
        null::int as points,
        false     as is_in_current_season
    from {{ ref('stg_fpl__historical_teams') }} ht
    where ht.team_code is not null
      and not exists (
          select 1 from current_teams ct where ct.team_code = ht.team_code
      )
    order by ht.team_code, ht.season desc

)

select * from current_teams
union all
select * from historical_only_teams
