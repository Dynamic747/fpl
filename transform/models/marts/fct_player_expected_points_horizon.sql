{#
    Grain: one row per current-squad player. Discounted sum of
    fct_player_expected_points_by_gameweek across the prediction horizon
    (default {{ var('prediction_horizon_gameweeks') }} gameweeks), used for
    season-aware initial squad selection so a player isn't picked purely
    on one week's fixture.

    Discount (0.95 per week further out) is gentle — team strength doesn't
    change fast, so a fixture 6 weeks out is still real signal, just
    slightly less certain than next week (rotation/form/injury risk grows
    with distance). This is a full-horizon planning aid, not a
    week-to-week decision input — use fct_player_expected_points for that.
#}

select
    player_code,
    web_name,
    position_id,
    current_team_code,
    current_price,
    sum(expected_points * power(0.95, weeks_ahead)) as horizon_expected_points,
    sum(fixture_count)                              as horizon_fixture_count,
    count(*)                                         as horizon_gameweeks
from {{ ref('fct_player_expected_points_by_gameweek') }}
group by player_code, web_name, position_id, current_team_code, current_price
order by horizon_expected_points desc
