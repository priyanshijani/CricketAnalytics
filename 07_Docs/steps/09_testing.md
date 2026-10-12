# Step 9 · Testing and validation

> **Intent:** prove, with repeatable checks, that data is processed correctly, business rules are right, data flows
> end to end, dashboards match the database, and bad data is handled.

**Files:** `06_Tests/` — `run_sql_tests.bat`, `sql/`, `test_cases/`, `results/`, `traceability_matrix.md`

## What is tested

| Suite | Proves | Checks |
|---|---|---|
| `check_reconciliation.sql` | Source → staging → warehouse → export counts balance; every file read = loaded + rejected | 19 |
| `check_business_rules.sql` | Batting average, strike rate, economy, win %, overs notation and edge cases | 25 |
| `check_referential_integrity.sql` | All 36 foreign keys enabled, trusted and violation-free | 15 |
| `check_rpt_views.sql` | Reporting views agree with the warehouse facts | 30 |
| `check_security.sql` | Each login can do exactly what it should, and nothing more | 19 |
| Test cases (`test_cases/`) | Planted DQ issues, reruns, corrected / duplicate / new / malformed files, dashboard-vs-SQL figures | per file |

## Latest result

**106 of 108 pass** (`06_Tests/results/2026-10-07_full_test_run.md`). The two failures are genuine defects in the
generated source data that no DQ rule catches yet (a bowler over the 4-over limit; chases that continued after the
target), recorded as the next rules to add (`assumptions_limitations.md`).

## How to run

Double-click `06_Tests\run_sql_tests.bat` after a pipeline run. Every requirement → test → latest result is in
`06_Tests/traceability_matrix.md`.
