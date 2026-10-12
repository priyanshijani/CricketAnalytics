# Business Rules

Every business calculation is defined once, as a function in the `rpt` schema
(`03_Alteryx/reporting_views/rpt_reporting_views.sql`). Every reporting view calls these functions, so the
Tableau dashboards, the CSV export (workflow `06`) and any ad hoc query compute the same number the same way.
`06_Tests/sql/check_rpt_views.sql` checks the rules against the warehouse facts.

## Calculations

| Measure | Definition | Function | Edge case |
|---|---|---|---|
| Batting average | Runs ÷ times dismissed | `rpt.fn_BattingAverage` | NULL when never dismissed (a not-out batter has no average, not an infinite one) |
| Strike rate | Runs × 100 ÷ balls faced | `rpt.fn_StrikeRate` | NULL when no ball faced (guards divide-by-zero) |
| Balls faced | Every delivery to the batter except wides | (warehouse load) | A no-ball counts as a ball faced |
| Legal ball | A delivery that is neither a wide nor a no-ball | (warehouse load) | Used for overs and economy |
| Overs | Legal balls in cricket notation: 23 balls = 3.5 overs | `rpt.fn_OversFromBalls`, `rpt.fn_BallsFromOvers` | 3.5 overs is 23 balls, not 3.5 × 6 |
| Economy | Runs conceded × 6 ÷ legal balls (runs per over) | `rpt.fn_Economy` | NULL when no legal ball bowled |
| Runs conceded (bowler) | Runs off the bat + wides + no-balls | (warehouse load) | Byes and leg-byes are not charged to the bowler |
| Bowler's wicket | A dismissal credited to the bowler | (warehouse load) | Run outs are wickets for the team, not the bowler |
| Bowling average | Runs conceded ÷ wickets | `rpt.fn_BowlingAverage` | NULL when no wicket taken |
| Win percentage | Wins ÷ decided matches × 100 | `rpt.fn_WinPct` | A decided match has a result: a tie counts (decided without a winner), a super-over match counts (it has a winner); no-result and abandoned matches do not |
| Match result (per team) | Won / Lost / Tied / NoResult / Abandoned | `rpt.TeamMatch.Result` | A super-over match is Won / Lost from the super-over winner |
| Match phase | Overs 1–6 Powerplay, 7–15 Middle, 16–20 Death | `rpt.fn_Phase` | T20 phases; the data is T20 only |
| Home match | The venue code starts with the team code (`MUM01` is Mumbai's home) | `rpt.fn_IsHome` | Assumption of this dataset: `Dim_Venue` has no home-team attribute |
| Impact points | Runs + 20 per wicket in a match | `rpt.fn_ImpactPoints` | A simple combined batting-and-bowling value for comparing all-rounders; the weighting is a documented assumption |
| Consistency | Coefficient of variation of runs per innings (standard deviation ÷ mean) | `rpt.PlayerCareer.RunsVariationCoefficient` | Lower = more consistent. NULL under 5 innings batted |
| Within-season form | Wins ÷ decided matches so far this season, after each match | `rpt.TeamMatch.RunningWinPct` | Equals the season's win % after the team's last match of the season |
| Leaderboard rank | Rank by career runs, wickets, impact per match (ties share a rank) | `rpt.PlayerCareer.RunsRank` / `WicketsRank` / `ImpactRank` | A top-10 filter on the rank stays correct as data is added |
| Fifty / hundred | 50–99 runs / 100+ runs in an innings | `rpt.BattingInnings` | |

## Dashboard decision rules

The rules above are facts about the data and live in SQL. The rules below decide how a dashboard *judges* those
facts (is a difference real, is a sample big enough, what is "close"). They are presentation choices, so they
live in the Tableau workbook as calculated fields, each defined once.

| Rule | Definition | Where it shows |
|---|---|---|
| Coin-flip benchmark | A win rate is compared with 50%; it is a real edge only if \|rate − 0.5\| > 1.96 × √(0.25 ÷ n) (95% confidence, normal approximation) | Toss and batting-first verdicts (Overview, Trends) |
| Bat first vs chase | Pooled two-proportion test at 95%: "clear edge" or "a lean, not a rule" | Team insight line |
| Small sample | Win-rate bars resting on fewer than 3 decided matches are grey | Team: head to head, venue, bat first or chase |
| League benchmark | The same measure over every player (or team) in the chosen season | Player KPIs and phase charts; Team average score |
| Close finish | Tied, super over, or won by ≤ 10 runs or ≤ 2 wickets; no-result and abandoned matches excluded | Overview and Trends tiles; Trends "Close finishes by season" |
| Turning point | The over with the most runs, and the over with the most wickets (fewest runs breaks a tie), in the selected match | Match centre insight lines |

## Scope rules

- **Team names:** each match shows the team's name at the time (`Dim_Team` Type-2 history: Delhi Falcons in
  2023, Delhi Comets from 2024). Every team view also carries `TeamCurrentName` for trends across a rename.
- **Ball-level statistics** (batting, bowling, phases, partnerships, fall of wicket, over progression) exclude
  matches whose ball-by-ball the DQ gate held back (`BallByBallStatus = 'Held'`). Match results and innings totals
  include every accepted match.
- **Incomplete matches** are flagged, not hidden: `rpt.Match.IsComplete = 0` and `rpt.TeamMatch.IsComplete = 0`
  mark matches with a rejected innings or held ball-by-ball. An abandoned match with no play is complete.
- **Partnerships:** the second partner is "Unknown (did not face a ball)" when they never faced a delivery -
  ball-by-ball records only the striker.
- **Season** is the match's season label from the source (calendar year in this dataset).
- **File status** (`rpt.DQFileStatus.Status`) is the outcome of validating the file's content: `New` (loaded) or
  `Rejected`. A re-run logs an unchanged file again as a duplicate; that is a re-delivery, counted in
  `TimesReceived`, not a new outcome. A file whose first arrival was a copy of another file stays `Duplicate`.
- **Row outcome** (`rpt.DQRowOutcome`): every row checked by the DQ gate gets one outcome, its root cause first:
  bad record > duplicate file > parent rejected > held (match incomplete) > flagged > accepted. Accepted and flagged
  rows reached the warehouse. The current state (`IsCurrent = 1`) counts each file once and master data as of the
  latest run, because master data is re-checked in full on every run.
- **Load status** (`rpt.LoadStatus`) shows each workflow's last *finished* run (Succeeded, Failed or Abandoned):
  workflow `06` exports it while `06` and the orchestrator are still running.

## Reporting views

| View | Grain | Answers |
|---|---|---|
| `rpt.Match` | Match | Match dashboard; toss and batting-first effect (questions 1, 9); result types over time (11) |
| `rpt.TeamMatch` | Team × match | Team dashboard; within-season form via `SeasonMatchNo` (2); head-to-head (7); venue and home/away |
| `rpt.TeamSeason` | Team × season | Team performance by season; most wins; win % |
| `rpt.OverProgression` | Innings × over | Run-rate worm and manhattan charts |
| `rpt.FallOfWicket` | Innings × wicket | Match scorecards |
| `rpt.Partnership` | Innings × partnership | Top-order combinations and their results (4) |
| `rpt.BattingInnings` / `rpt.BowlingInnings` | Player × innings | Player dashboard; home vs away (5) |
| `rpt.PlayerMatch` | Player × match | Basis for consistency and impact |
| `rpt.PlayerSeason` | Player × season | Player trends; improving or declining year on year (8) |
| `rpt.PlayerCareer` | Player | Consistent vs explosive (12); all-rounder impact per match (10) |
| `rpt.PlayerPhase` | Player × season × phase × discipline | Pressure batting in the death overs (3); powerplay vs death economy (6) |
| `rpt.PlayerRanking` | Player × format × date × discipline | Ranking history |
| `rpt.PlayerSeasonHistory` | Player × season × format | Historical-statistics feed |
| `rpt.Player` | Player | Attributes for filters and labels |
| `rpt.DQFileStatus`, `rpt.DQIssue`, `rpt.DQScoreTrend`, `rpt.LoadStatus` | File / issue / run / workflow | Data Quality & Load Status view |
| `rpt.DQRowOutcome` | DQ run × entity × outcome | Rows checked, % accepted, why rows did not pass (bad record, duplicate file, parent rejected, held: match incomplete, flagged) |
