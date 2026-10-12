# Tableau workbook test results - 2026-10-07

Tableau Public 2026.2 (Windows) on the extracts from orchestrator run `20261007` (all 7 stages Succeeded).
Cases defined in `../test_cases/tableau_test_cases.md`. Each dashboard was opened in Tableau Public and checked
on screen; numbers were compared with queries on the `rpt` views.

| ID | Result | Actual |
|---|---|---|
| TAB-TC01 | Pass | 19 / 19 views: `.hyper` rows = CSV rows = manifest. |
| TAB-TC02 | Pass | `load-workbook: ok`, no error dialog; 15 data sources accepted as extracts. |
| TAB-TC03 | Pass | Workbook + extracts copied to a different root folder: opened and the Overview showed all data. |
| TAB-TC04 | Pass | All 8 dashboards and the 5-point Season Story render every chart, legend, picker and button (re-checked after the storytelling update). |
| TAB-TC05 | Pass | 119 / 3 / 39,295 / 1,703 / 56% (SQL 55.7%); Bangalore Royals 20; Naveen Bhatt 968; Amit Sinha 42. Player profile (Naveen Bhatt) 28 matches, average 38.7, strike rate 140.3, 30 wickets, economy 8.44 = `rpt.PlayerCareer`. Match M0120: MUM 153/7 v DEL 180/8, Delhi Comets won by 2 wickets = `rpt.Match`. |
| TAB-TC06 | Pass (defaults) | Default team, player and match drive their dashboards; lists are read from the data on open. Interactive change of the picker not yet exercised by hand. |
| TAB-TC07 | Pass | Death strike rate top: Dhruv Chauhan 196.8 (62 balls) = SQL ranking; 15 players on each chart. |
| TAB-TC08 | Pass | 129 files, 4 rejected (M0013.json and the 3 MALFORMED files), 1,076 open issues; every workflow Succeeded. Row tiles (added later the same day): 30,758 rows checked, 96.6% accepted, 1,034 held or rejected, 38 flagged = `rpt.DQRowOutcome` and `audit.DQRunEntity`; reasons: held 772, parent rejected 253, bad record 8, duplicate file 1. |
| TAB-TC09 | Not run | Needs a `demo_changes` pass (Additional Challenge rehearsal). |
| TAB-TC10 | Pass | Bangalore Royals 20 of 29 (69%); batting first 13 / 16 (81%), chasing 7 / 13 (54%); Naveen Bhatt strike rate 140.3 vs league 135.5, average 38.7 vs 22.3, economy 8.44 vs 8.77; most impact Nikhil Bhatt 69.7; M0120 top scorer Chetan Desai 48 (33), best bowling Naveen Sinha 4-33; main DQ reason Held: match incomplete 772 - all equal to the exports. |
| TAB-TC11 | Pass | n = 115 (toss) / 114 (batting first): margin 1.96 x sqrt(0.25 / 115) = 9.1 pts; toss 55.7% (z = 1.2), batting first 57.9% (z = 1.7) - both within chance, as the verdict says. |
| TAB-TC12 | Pass | Labels "x of n" on head to head, venue and batting first / chasing; 1-of-1 venues grey; 50% lines drawn; league lines on phase charts (death batting league strike rate 136.8 = export); median lines on the scatter. |
| TAB-TC13 | Pass (dialog) | Actions dialog: 10 parameter actions (type icon, field Team / Player) and 2 filter actions recognised. Clicking a mark not yet exercised by hand. |
| TAB-TC14 | Partly | Buttons render and the story shows its 5 points; clicking the buttons not yet exercised by hand. |

## Defects found and fixed while building

| Defect | Fix |
|---|---|
| Tableau Public refused live CSV sources ("must use extracts") and a data source joining several `.hyper` files | Workflow `06` writes one `.hyper` per view; one data source per extract |
| Export stopped: "This database does not support 128-bit numerics" (`rpt.TeamMatch.RunningWinPct`, a DECIMAL division) | Cast to `DECIMAL(9,4)`; no `rpt` decimal now exceeds precision 18 |
| `rpt.DQFileStatus` showed every unchanged file as `Duplicate` after a re-run; `rpt.LoadStatus` showed `06` and the orchestrator as `Started` (the export runs mid-run) | File status = outcome of validating the content, plus `TimesReceived`; load status = last finished run |
| Running win % restarted at every match (Tableau table calculation on a continuous axis) | Computed in SQL: `rpt.TeamMatch.RunningWinPct` |
| Toss effect stacked two averages (63% + 89%) | Bars side by side per toss decision |
| Layout, labels, tooltips and colours (tiles collapsing, empty label fields, blank sheets) | Fixed in the workbook: fixed tile positions, every label field on the label shelf, explicit text formats |
| Categorical colours ignored (Tableau defaults shown) | Colour maps written as Tableau saves them: data-source column-instance + per-value maps, no worksheet colour encoding |
| Insight sentences blank | Text-valued aggregate calculations must be discrete (`usr:Calc:nk`) |
| "Main reason rows did not pass" showed Accepted | Two filters on one field: only one is kept; the ranking calc now counts only rows not passed |
| Go-to-sheet actions not recognised by Tableau | Replaced by navigation buttons (pattern from a Tableau-saved workbook) after a click-to-pick parameter action |
