# 05_Tableau

Step 4: dashboards. `workbook/CricketAnalytics.twb` is the Tableau Public workbook.

## How the workbook reads the data

- Tableau Public has no database connectors and accepts only extracts. Workflow `06` therefore writes every
  reporting view as a Tableau extract, `04_Prepared/rpt_<View>.hyper`, next to its CSV.
- Each data source in the workbook reads **one** `.hyper` file through a path relative to the workbook
  (`../../04_Prepared/rpt_<View>.hyper`). Opened from any clone of the repository, it finds its data with no
  setup. Tableau Public refuses a data source that joins several `.hyper` files, so there is one data source
  per view; the views were designed so that each chart needs only one.
- The workbook shows whatever the last pipeline run exported. There is no extract refresh: run the pipeline,
  then open (or reopen) the workbook. Close Tableau before running the pipeline - an open workbook locks the
  `.hyper` files and workflow `06` cannot replace them.
- The picker lists (match, team, player, season) are read from the data each time the workbook opens, so new
  matches, players and seasons appear without editing the workbook.

## Look and feel (GPL template)

Every dashboard uses the same template:

- A navy header band with the GPL logo (`workbook/gpl_logo.png`), the dashboard
  title and, in smaller type, the questions the dashboard answers.
- Filters (pickers) first, then a row of KPI tiles, then the charts; each chart sits on a white card on a light
  grey page.
- One type scale (Tableau Book / Semibold) and one colour scheme: navy for any single-series chart, and a fixed
  colour per category value (Home / Away, phases, roles, result types, seasons, teams) that is the same on every
  chart. Continuous measures use one blue scale (red-grey-green when the measure has a good and a bad side).

## Storytelling and decision rules

- **Insight line first.** Every dashboard opens with a ▶ Insight sentence computed from the data (top team,
  toss verdict, team's toss call, player vs league, top performers, main DQ reason). It is a calculation, not
  typed text, so it stays true when new data arrives.
- **Sample size is always visible.** Win-rate bars carry "wins of matches" labels; bars resting on fewer than 3
  matches are grey. Opening pairs need 3+ innings, leaderboards keep their minimum-balls rules.
- **Benchmarks.** Win rates are drawn against a 50% line (a coin flip); player strike rate, average and economy
  against the league average for the same season (and phase); the consistency scatter has median lines that split
  players into quadrants.
- **Significance, not eyeballing.** The toss / batting-first verdict compares each rate with 50% at 95% confidence
  (normal approximation: margin = 1.96 x sqrt(0.25 / n)). The Team page compares batting first and chasing with a
  pooled two-proportion test and says "clear edge" or "a lean, not a rule".
- **Context on every headline number.** Count tiles carry a rate underneath (runs → average score, wickets →
  per innings, matches → seasons covered), so a total is never shown without a sense of scale.
- **Close finishes.** Share of decided matches that were tied, went to a super over, or were won by 10 runs or
  fewer / 2 wickets or fewer - a competitive-balance measure, shown overall and by season against the all-season
  average.
- **Turning points.** Match centre names the biggest over and the most damaging over of the selected match.
- **Season Story.** Five story points (table, winners, toss myth, player value, data trust) walk a reader through
  the findings in order; it doubles as the demo script.

## Interactivity

- Pickers (parameters) for season, team, player and match; they are workbook-wide, so a choice carries across pages.
- Click a team or player on Overview, Leaderboard 2.0 or Player leaderboards to pick it (parameter actions), then
  use the **Team page → / Player profile →** button to open that page already showing it.
- Click a venue on Trends to filter the toss chart; click a rule on Data Quality to filter the owners chart.
- Every chart has a formatted tooltip that states the figure and the number of matches or balls behind it.

## Dashboards

| Dashboard | Answers |
|---|---|
| Overview (pick a season) | Insight: most wins and the toss / batting-first verdict; matches, runs, wickets (each with a per-match rate), close-finish rate; teams with the most wins; win % by team and season; top 10 run scorers and wicket takers |
| Leaderboard 2.0 (pick a season) | Points table of the top 5 teams: position (trophy / medals), played, won, lost, no result, net run rate, form of the last five, points; the table topper on top |
| Team (pick a team and a season) | Average score vs the league; win % by season vs other teams; Q2 within-season form; Q7 head to head; win % by venue (home / away); batting first vs chasing; Q4 opening pairs and how often the team won |
| Player (pick a player and a season) | Career figures; Q8 runs by season and wickets / economy by season; Q5 home vs away; strike rate and economy by phase |
| Player Leaderboards | Q12 consistent vs explosive; Q10 impact per match; Q3 death-over strike rate (top 15); Q6 powerplay vs death economy (top 15); Q8 improving and declining players by season |
| Match (pick a match) | Summary card; turning points (biggest over, most damaging over); run worm; runs per over per innings; batting and bowling scorecards; fall of wickets |
| Trends | Q11 how matches were decided, winning margins and close-finish rate by season; Q1 / Q9 toss and batting-first effect by venue; runs per over by phase and season; venue profile (average first-innings score, how often chasers win) |
| Data Quality | Rows checked, % accepted, rows held or rejected, rows flagged; why rows did not pass (by reason and entity); % of rows not passed per DQ run (circle size = rows checked); files received / rejected, open issues; files by outcome; rejected files; each workflow's last finished run; issues by rule and by owner |

Q-numbers are the additional questions in `07_Docs/00_Project_Plan.md` section 3. Every number comes from an
`rpt` view; the business rules behind them are in `07_Docs/business_rules.md`.

## Changing the workbook

Open the workbook in Tableau Public (saving locally needs Tableau Public 2026.2.3 or later). After a save, check that
every data source still points to `../../04_Prepared/...` and not to an absolute path, so the workbook keeps working
from any clone. The workbook stays local - it is not published to the Tableau Public gallery.
