# CSV Schema

## deliveries/deliveries_<season>.csv

One row per legal or extra delivery. Grain: match + innings + over + ball (extras share the ball number
of the legal delivery they preceded, since they don't advance the over).

| Column | Type | Notes |
|---|---|---|
| match_id | string | Foreign key to the match JSON's `match_id` |
| innings_no | integer | 1 or 2 |
| over_no | integer | 1-20 |
| ball_no | integer | Sequence within the over, counting every delivery attempt including wides/no-balls - not capped at 6, since an over with an extra has more than six deliveries |
| batsman_code | string | Foreign key to CricketSource.Players |
| bowler_code | string | Foreign key to CricketSource.Players |
| runs_off_bat | integer | Can be negative in one planted invalid-value case |
| extra_runs | integer | 0 or 1 |
| extra_type | string | "Wide", "NoBall", or blank |
| is_wicket | string | "Y" or "N" |
| dismissal_type | string | Blank when not a wicket |
| dismissed_player_code | string | Blank when not a wicket |

## player_rankings/player_rankings.csv

Grain: player + format + discipline + ranking date.

| Column | Type | Notes |
|---|---|---|
| player_code | string | Foreign key to CricketSource.Players |
| player_name | string | Redundant display name - one planted casing mismatch against the SQL master |
| format_code | string | |
| discipline | string | Batting / Bowling / AllRounder |
| ranking_date | string | **dd/mm/yyyy** - deliberately different format from historical_stats.csv |
| rank_position | integer | |
| rating_points | integer | |

## historical_stats/historical_stats.csv

Grain: player + season + format.

| Column | Type | Notes |
|---|---|---|
| player_code | string | Foreign key to CricketSource.Players |
| player_name | string | |
| season | string | |
| format_code | string | |
| matches_played | integer | |
| runs_scored | integer | |
| wickets_taken | integer | |
| season_start_date | string | **yyyy-mm-dd** (ISO) - deliberately different format from player_rankings.csv |
