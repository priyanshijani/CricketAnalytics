# Tableau workbook test cases

Under test: `05_Tableau/workbook/CricketAnalytics.twb` and the
extracts it reads, `04_Prepared/rpt_*.hyper` (written by workflow `06`). Start state: a successful orchestrator run.

| ID | Case | Expected outcome | How to verify |
|---|---|---|---|
| TAB-TC01 | Extracts reconcile | For every view: rows in `rpt_<View>.hyper` = rows in `rpt_<View>.csv` = `_manifest.csv` row count | Count `"Extract"."Extract"` in each `.hyper` (Hyper API) and compare |
| TAB-TC02 | Workbook opens in Tableau Public | Tableau Public 2026.2 loads it with no error or warning dialog; every data source is accepted as an extract | Open the file; the Tableau log shows `load-workbook` `ok` and no `sev:error` lines |
| TAB-TC03 | Portable | Copied with `04_Prepared/*.hyper` into a different root folder (same layout), it opens and every dashboard shows data | Copy, open, look at each dashboard |
| TAB-TC04 | Every dashboard renders | All 8 dashboards and the Season Story show every chart, legend, picker and button; no empty tile | Open each dashboard and story point |
| TAB-TC05 | Numbers match SQL | Overview: 119 matches, 3 seasons, 39,295 runs, 1,703 wickets, toss winner won 56%; most wins Bangalore Royals 20; top scorer Naveen Bhatt 968; top wicket taker Amit Sinha 42 | The same figures from `rpt` views in SQL Server |
| TAB-TC06 | Pickers drive their dashboards | Picking a team / player / match changes every chart on that dashboard that follows it; the lists come from the data | Pick another value; check a chart against SQL |
| TAB-TC07 | Top-N leaderboards | Death-over strike rate and death economy show 15 players each, ranked after the phase filters, with the minimum-balls rule applied | Compare with a SQL ranking (`rpt.PlayerPhase`) |
| TAB-TC08 | Data Quality view | Files received 129, rejected 4, open issues 1,076; every workflow's last finished run Succeeded | `rpt.DQFileStatus`, `rpt.DQIssue`, `rpt.LoadStatus` |
| TAB-TC09 | New data reaches the workbook | After a pipeline run with new data (Tableau closed), reopening shows it without any refresh step | Stage a `demo_changes` category, run the orchestrator, reopen |
| TAB-TC10 | Insight lines are computed from the data | Each dashboard's ▶ Insight line matches SQL / the exports: most wins (Overview), toss / batting-first verdict (Overview, Trends), batting first vs chasing (Team), player vs league (Player), most impact (Player leaderboards), top scorer and best bowler (Match), main reason rows did not pass (Data Quality) | Recompute each figure from the `rpt` views |
| TAB-TC11 | Toss verdict is a valid significance test | Verdict compares each rate with 50% at 95% (normal approximation, margin 1.96 x sqrt(0.25 / n)); with 115 / 114 decided matches the margin is 9 pts, so 56% and 58% are "within chance" | Recompute the margin and both z-scores |
| TAB-TC12 | Small samples are visible | Win-rate bars show "wins of matches" labels; bars on fewer than 3 matches are grey; every win-rate chart has a 50% line; player phase charts and the death leaderboard have a league-average line; the consistency scatter has median lines | Look at Team, Trends, Player, Player leaderboards |
| TAB-TC13 | Click-to-pick actions | The Actions dialog lists 10 "Pick team / Pick player" parameter actions and 2 filter actions (Trends venue, Data Quality rule), all recognised (type icon and field shown); clicking a team or player sets the Team / Player picker | Dashboard > Actions; click a bar, then the Team page / Player profile button |
| TAB-TC14 | Navigation and story | Team page / Player profile buttons open those dashboards; the Season Story has 5 story points, each showing its dashboard | Click the buttons; step through the story |
