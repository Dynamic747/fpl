{#
    Conformed across seasons: team rosters change every season (promotion/
    relegation), so a current-only dimension would leave historical fact
    rows (referencing relegated clubs) with orphaned foreign keys.
    current_teams wins on any team_code overlap; teams no longer in the
    Premier League get null strength/current attributes.

    Strength ratings: the FPL API reports these as 0 for every team before
    the season's ratings are published (confirmed empirically pre-GW1), so
    strength_* falls back to that team's most recent historical season's
    rating, and finally to the current league average for teams with no
    history at all (this season's promoted clubs) — a 0 here would
    otherwise silently zero out the fixture-difficulty calc downstream.
#}

with current_teams_raw as (

    select
        team_code,
        team_id  as current_team_id,
        team_name,
        team_short_name,
        nullif(strength, 0)               as strength,
        nullif(strength_overall_home, 0)  as strength_overall_home,
        nullif(strength_overall_away, 0)  as strength_overall_away,
        nullif(strength_attack_home, 0)   as strength_attack_home,
        nullif(strength_attack_away, 0)   as strength_attack_away,
        nullif(strength_defence_home, 0)  as strength_defence_home,
        nullif(strength_defence_away, 0)  as strength_defence_away,
        league_position,
        points,
        true as is_in_current_season
    from {{ ref('stg_fpl__teams') }}

),

most_recent_historical as (

    select distinct on (team_code)
        team_code,
        strength,
        strength_overall_home,
        strength_overall_away,
        strength_attack_home,
        strength_attack_away,
        strength_defence_home,
        strength_defence_away
    from {{ ref('stg_fpl__historical_teams') }}
    order by team_code, season desc

),

league_avg_historical as (

    select
        avg(strength)               as strength,
        avg(strength_overall_home)  as strength_overall_home,
        avg(strength_overall_away)  as strength_overall_away,
        avg(strength_attack_home)   as strength_attack_home,
        avg(strength_attack_away)   as strength_attack_away,
        avg(strength_defence_home)  as strength_defence_home,
        avg(strength_defence_away)  as strength_defence_away
    from most_recent_historical

),

current_teams as (

    select
        c.team_code,
        c.current_team_id,
        c.team_name,
        c.team_short_name,
        coalesce(c.strength, h.strength, la.strength)                             as strength,
        coalesce(c.strength_overall_home, h.strength_overall_home, la.strength_overall_home)   as strength_overall_home,
        coalesce(c.strength_overall_away, h.strength_overall_away, la.strength_overall_away)   as strength_overall_away,
        coalesce(c.strength_attack_home, h.strength_attack_home, la.strength_attack_home)     as strength_attack_home,
        coalesce(c.strength_attack_away, h.strength_attack_away, la.strength_attack_away)     as strength_attack_away,
        coalesce(c.strength_defence_home, h.strength_defence_home, la.strength_defence_home)  as strength_defence_home,
        coalesce(c.strength_defence_away, h.strength_defence_away, la.strength_defence_away)  as strength_defence_away,
        c.league_position,
        c.points,
        c.is_in_current_season
    from current_teams_raw c
    left join most_recent_historical h on c.team_code = h.team_code
    cross join league_avg_historical la

),

historical_only_teams as (

    select distinct on (ht.team_code)
        ht.team_code,
        null::int as current_team_id,
        ht.team_name,
        ht.team_short_name,
        ht.strength,
        ht.strength_overall_home,
        ht.strength_overall_away,
        ht.strength_attack_home,
        ht.strength_attack_away,
        ht.strength_defence_home,
        ht.strength_defence_away,
        null::int as league_position,
        null::int as points,
        false     as is_in_current_season
    from {{ ref('stg_fpl__historical_teams') }} ht
    where ht.team_code is not null
      and not exists (
          select 1 from current_teams_raw ct where ct.team_code = ht.team_code
      )
    order by ht.team_code, ht.season desc

)

select * from current_teams
union all
select * from historical_only_teams
