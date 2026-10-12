# Export and orchestration test results - 2026-10-06

Alteryx Designer 2026.2 (AMP engine, run through `AlteryxEngineCmd.exe`) against SQL Server 2019 Express
(15.0.2000.5). Cases defined in `../test_cases/export_orchestration_test_cases.md`.

| ID | Result | Actual |
|---|---|---|
| EXP-TC01 | Pass | 19 files for 19 views. |
| EXP-TC02 | Pass | Every file's rows = manifest = view count; 18,479 rows exported in total. |
| EXP-TC03 | Pass | Manifest columns present; BatchId `06_export_reporting_20261006124339` matches the run log. |
| ORC-TC01 | Pass | Run `20261006124339`: all 8 containers in 3 min 17 s. 01: 168 rows; 02: 362; 03: 30,244; 04: 30,758 in, 29,724 valid, 1,034 rejected; 04b: 1,076 report rows; 05: 41,098 staged and published; 06: 18,479 exported. `check_dw_load.sql` and `check_rpt_views.sql` (30 / 30) as the baseline. Exit code 1 (warnings only). |
| ORC-TC02 | Pass | One `RunStamp` across all 8 workflows. |
| ORC-TC03 | Pass | Observed on a real failure: the first orchestrated run stopped in `04` with "Not enough memory to run the workflow" (about 1 GB free); 04b-06 did not start; exit code 2. |
| ORC-TC04 | Pass | The next run refused: "Pre-flight failed: A previous run is stuck in Started (00_orchestrator, 04_dq_validation)". |
| ORC-TC05 | Pass | `usp_AbandonStuckRuns` recorded 2 Abandoned rows; `vw_StuckRun` empty; the rerun passed pre-flight. |
| ORC-TC06 | Pass | `run_summary_latest.csv` written with 7 Succeeded stages. |

## Defects found and fixed during testing

| Defect | Fix |
|---|---|
| `[Engine.WorkflowFileName]` inside a stage macro returns the orchestrator's name, so every stage would log as `00_orchestrator` | Each stage writes its own name as a literal |
| `03_ingest_csv` was back to "Append" (a Designer save of an older copy), doubling `stg.BallByBallRaw` to 58,184 rows | Restored "Delete Data & Append"; each stage is now kept only as its `.yxmc` so there is one copy to save |
| A failed `04` leaves a partial DQ batch (exceptions and `*Valid` rows written, file control not) | Known limitation: recovery is abandon + section 2 of `reset_pipeline_state.sql` (`07_Docs/deployment.md`) |
