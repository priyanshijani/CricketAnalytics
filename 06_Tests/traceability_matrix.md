# Requirement traceability matrix

Every requirement in `07_Docs/00_Project_Plan.md` (section 2) and every business question (section 3), traced
to the tests that verify it and their latest result. Executed 2026-10-07; evidence in `06_Tests/results/`.

Status: **Pass** - verified; **Partial** - verified except the item named; **Open** - not yet executed.

## Requirements

| # | Requirement | Verified by | Status | Evidence |
|---|---|---|---|---|
| R1 | SQL Server master / reference data (teams, players, venues) | RC01-RC06 | Pass | `2026-10-07_full_test_run.md` |
| R2 | JSON match data, nested structure | DQ-TC01-TC04, RC10-RC11 | Pass | `2026-10-05_dq_validation.md`, `2026-10-07_full_test_run.md` |
| R3 | CSV detailed data (ball-by-ball, rankings, historical) | DQ-TC (schema check DQ13), RC08, RC12 | Pass | `2026-10-05_dq_validation.md`, `2026-10-07_full_test_run.md` |
| R4 | Alteryx for ETL and data preparation | ORC-TC01-TC02, EXP-TC01-TC03 | Pass | `2026-10-06_export_orchestration.md` |
| R5 | Microsoft SQL Server as the database | Setup scripts applied; RI01-RI02 | Pass | `2026-10-07_full_test_run.md` |
| R6 | Tableau for visualization | TAB-TC01-TC08, TAB-TC10-TC12 | Pass | `2026-10-07_tableau_workbook.md` |
| R7 | Detect and handle data-quality issues, with traceability | DQ-TC01-TC11, BR05, RI11-RI13 | Pass | `2026-10-05_dq_validation.md`, `2026-10-07_full_test_run.md` |
| R8 | Reliability, error handling, logging | ORC-TC03-TC05 (stop on failure, stuck-run guard, recovery), RC07-RC09, RI14-RI15 | Pass | `2026-10-06_export_orchestration.md`, `2026-10-07_full_test_run.md` |
| R9 | Player / team / match / trends analysis | TAB-TC05, BR14-BR22, RPT-TC01-TC06 | Pass | `2026-10-07_tableau_workbook.md`, `2026-10-06_reporting_security.md` |
| R10 | Dashboards usable and interactive | TAB-TC04, TAB-TC06, TAB-TC12-TC14 | Partial - pickers, 12 actions (Actions dialog), buttons and story verified to load and render; clicking marks and buttons by hand pending | `2026-10-07_tableau_workbook.md` |
| R11 | Identify and address performance issues | PERF-TC01-TC02 | Pass | `2026-10-07_full_test_run.md` |
| R12 | Authentication, authorization, least privilege | SEC-TC01-TC05 | Partial - SEC-TC06 (pipeline running under the least-privilege logins) is a deployment step | `2026-10-06_reporting_security.md`, `2026-10-07_full_test_run.md` |
| R13 | Reproducible deployment, no hardcoding | TAB-TC03 (workbook from another folder), no absolute paths in tracked files | Partial - fresh-machine dry run not yet done | `2026-10-07_tableau_workbook.md` |
| R14 | Test coverage: correctness, calculations, flow, dashboard consistency, invalid data | This matrix; `run_sql_tests.bat` (108 checks) | Pass | `2026-10-07_full_test_run.md` |
| R15 | All named deliverables | Plan section 11 checklist | Partial - PowerPoint presentation not built yet | `07_Docs/00_Project_Plan.md` |
| R16 | Additional Challenge: new / corrected / duplicate / malformed files | DQ-TC05-TC08 (rerun, duplicate, corrected, new file); TAB-TC09 | Partial - DQ handling verified; full `demo_changes` rehearsal through to the dashboards pending | `2026-10-05_dq_validation.md` |

## Business questions

Assignment questions (plan section 3) and the twelve additional questions, each with the dashboard that answers
it and the check that its numbers are right.

| Question | Dashboard / chart | Numbers verified by |
|---|---|---|
| Team performance by season | Overview: win % by team and season; Team: win % by season | BR18, RPT-TC03 |
| Teams with the most wins | Overview: most wins | TAB-TC05 (Bangalore Royals 20 = SQL) |
| Consistently strong players | Player Leaderboards: consistent vs explosive | BR14-BR15, RPT-TC04 |
| Individual player trends over time | Player: runs by season | RPT-TC02 |
| Top contributors to team performance | Overview: top 10 run scorers / wicket takers; Leaderboards: impact per match | TAB-TC05 (Naveen Bhatt 968, Amit Sinha 42 = SQL) |
| Team performance by opponent | Team: head to head | BR20, RPT-TC03 |
| Performance by venue | Team: win % by venue; Trends: toss and batting first by venue | RPT-TC01 |
| Batting and bowling trends | Trends: runs per over by phase; Player: strike rate / economy by phase | RC12, BR17 |
| Q1 Toss and bat / field choice vs winning, by venue | Trends: toss effect by venue; batting first by venue | BR09, BR11 |
| Q2 Win rate within a season | Team: win % so far, match by match | BR21 |
| Q3 Best under pressure (death-over strike rate) | Leaderboards: death-over strike rate (top 15) | TAB-TC07 (Dhruv Chauhan 196.8 = SQL) |
| Q4 Most-used top-order combination and results | Team: opening pairs | RC12 (partnerships = innings), RI09 |
| Q5 Home vs away | Player: home vs away | BR14-BR15 |
| Q6 Powerplay vs death economy | Leaderboards: powerplay vs death economy; Player: economy by phase | BR17 |
| Q7 Head-to-head record | Team: head to head | BR20 |
| Q8 Improving or declining players | Leaderboards: runs vs previous season; Player: runs by season | RPT-TC02 |
| Q9 Toss effect by format or venue | Trends: toss effect by venue (one format in the data) | BR09 |
| Q10 All-rounder value per match | Leaderboards: impact per match | RPT-TC04 |
| Q11 Are matches getting closer | Trends: how matches were decided; average winning margin | BR10-BR11 |
| Q12 Consistent vs explosive | Leaderboards: consistent vs explosive | RPT-TC04 |

## Open findings

| Finding | Check | Status |
|---|---|---|
| 13 bowling spells longer than 4 overs (one of 12 overs) in the sample data | BR06 FAIL | Source-data defect not caught by any DQ rule - candidate rule |
| 42 of 112 decided matches where the chasing side batted on after passing the target (more than 6 runs over) | BR12 FAIL | Source-data defect not caught by any DQ rule - candidate rule |
