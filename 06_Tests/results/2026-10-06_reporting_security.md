# Reporting layer and security test results - 2026-10-06

Run against the baseline warehouse (workflows `04` → `04b` → `05`, verified by `check_dw_load.sql`) on
SQL Server 2019 Express (15.0.2000.5). Cases defined in `../test_cases/rpt_security_test_cases.md`.

| ID | Result | Actual |
|---|---|---|
| RPT-TC01 | Pass | 119 / 238 rows; every fact-based view equals its fact count. |
| RPT-TC02 | Pass | Batting runs 36,936 in every view; wickets 1,306; runs conceded 38,601; team runs 39,295; 0 innings whose final cumulative score differs from its total. |
| RPT-TC03 | Pass | 0 matches with an inconsistent Won / Lost pair; 115 wins; 4 tied and 4 no-result team rows. |
| RPT-TC04 | Pass | All guards hold. |
| RPT-TC05 | Pass | 0 batting rows for held matches; 3 matches flagged incomplete. |
| RPT-TC06 | Pass | DEL 2023 = Delhi Falcons; current name Delhi Comets on every season. |
| SEC-TC01 | Pass | 3 / 3 checks. |
| SEC-TC02 | Pass | 9 / 9 checks. |
| SEC-TC03 | Pass | 7 / 7 checks. |
| SEC-TC04 | Pass | 0 unreadable views. |
| SEC-TC05 | Pass | Passwords only in `config/local.config` (gitignored). |
| SEC-TC06 | Not run | Deployment step. |

## Defects found and fixed during testing

| Defect | Fix |
|---|---|
| `rpt.TeamSeason` failed to compile: `SUM` over a BIT | Cast `IsHome` to INT before summing |
| The reporting login could not read views that call `rpt.fn_*` ("EXECUTE permission denied on fn_IsHome") | SQL Server 2019 scalar-UDF inlining checks `EXECUTE` even inside a view; granted `EXECUTE` on the `rpt` schema to `report_reader` |
| The publish procedure's `TRUNCATE` would need `ALTER` for the ETL writer | Changed to `DELETE` |
| Test expectation: 4 incomplete matches | Wrong expectation - the abandoned M0061 is complete (nothing to record); 3 is correct |
