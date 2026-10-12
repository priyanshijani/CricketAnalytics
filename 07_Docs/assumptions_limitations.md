# Assumptions and Limitations

## Assumptions

| Area | Assumption |
|---|---|
| Data | All data is synthetic and fictitious (8 teams, 152 players, 3 seasons, 120 T20 matches), produced by `02_SampleData/generator/`. Data-quality issues are planted deliberately and catalogued in `02_SampleData/source/DATA_QUALITY_ISSUES.md`. |
| Format | T20 only: phases are overs 1–6 (powerplay), 7–15 (middle), 16–20 (death). |
| Season | The season label carried by each match (calendar year here). |
| Home match | A venue whose code starts with the team's code (`MUM01` is Mumbai's home); the master data has no home-team attribute. |
| Impact points | Runs + 20 per wicket: a simple, documented weighting for comparing all-rounders, not an industry standard. |
| Close finish | Tied, super over, or won by ≤ 10 runs or ≤ 2 wickets (no balls-remaining data exists to refine it). |
| Significance | Toss and batting-first verdicts use a 95% normal approximation against 50%; with ~115 matches the margin is about ±9 points. |
| Team names | A team's name history comes from the name carried in each match file (`Dim_Team` Type-2). |
| Environment | One Windows PC; SQL Server 2019+ with Windows authentication; Alteryx Designer 2026.2 (AMP); Tableau Public 2026.2. |

## Limitations of the prototype

| Limitation | Effect | Production answer |
|---|---|---|
| Tableau Public has no database connectors | Data reaches Tableau as `.hyper` files exported by workflow `06` | Tableau Server connects to `rpt` with a read-only login (`production_architecture.md`) |
| No server, scheduler or permissions in Tableau Public | Refresh = rerun pipeline and reopen; no row-level security | Event-driven extract refresh; RLS by user entitlement |
| Pipeline started by hand in Designer | No schedule or folder watch | Alteryx Server schedule or folder watcher |
| Alteryx connections use the Windows account of the person running Designer | The least-privilege logins exist and are tested (`security.md`), but the pipeline does not use them by default | Service accounts in Alteryx Server Data Connections |
| Processed files stay in the inbox | Each rerun logs unchanged files as duplicates (by design, never reprocessed) | Move files to `archive` / `error` after each run (folders and parameters already exist) |
| A rejected file is not re-validated after its master data is fixed | It must be re-sent (or its file-control rows removed) | A reprocess-request table the DQ gate honours |
| Data-quality rules test rows, not whole files | A file with half its rows missing passes every rule | Volume, distribution and freshness checks per file |
| DQ rules are edited in place and stored as SQL text | Old exceptions cannot be reproduced exactly after a rule changes | Versioned rules, reviewed through source control |
| Stage `04` writes several tables without one transaction | A crash mid-stage leaves a partial DQ batch (pre-flight refuses the next run until it is resolved) | One-transaction publish, as stage `05` already does |

## Known source-data defects (found by testing, not yet DQ rules)

| Check | Finding | Effect |
|---|---|---|
| BR06 | 13 bowling spells exceed the T20 limit of 4 overs | Included in bowling figures |
| BR12 | 42 of 112 chases continued after the target was passed (e.g. M0120: target 154, DEL 180/8) | Totals and run rates of those innings are inflated |

Both come from the sample-data generator. The next step of the data-quality cycle is to add them as **Flag** rules,
so the matches stay in the analysis with a warning (`06_Tests/results/2026-10-07_full_test_run.md`).
