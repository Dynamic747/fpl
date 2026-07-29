{#
    Grain: team x gameweek (current season). Flags blank gameweeks (a team
    has 0 fixtures that week) and double gameweeks (2+ fixtures), which
    matter a lot for chip timing (bench boost/triple captain want a DGW;
    free hit wants to route around a bad BGW).

    As of the initial fixture list, every gameweek has exactly 10 fixtures
    (every team plays once) — DGWs/BGWs get created later in the season by
    fixture rearrangements (cup replays, European clashes, postponements),
    which the FPL API/fixture list only reflects once actually confirmed.
    This model will automatically pick up any such rearrangement the next
    time raw fixtures data is re-ingested and this is rebuilt — no chip
    timing can be meaningfully planned before then, because the
    information it would be based on doesn't exist yet.
#}

with season_gameweeks as (

    select distinct gameweek_id
    from {{ ref('dim_gameweeks') }}
    where season = '{{ var("current_season") }}'

),

team_gameweeks as (

    select t.team_code, gw.gameweek_id
    from {{ ref('dim_teams') }} t
    cross join season_gameweeks gw
    where t.is_in_current_season = true

)

select
    tg.team_code,
    tg.gameweek_id,
    count(f.fixture_id)         as fixture_count,
    count(f.fixture_id) = 0     as is_blank_gameweek,
    count(f.fixture_id) >= 2    as is_double_gameweek
from team_gameweeks tg
left join {{ ref('fct_fixtures') }} f
    on f.gameweek_id = tg.gameweek_id
   and (f.home_team_code = tg.team_code or f.away_team_code = tg.team_code)
group by tg.team_code, tg.gameweek_id
