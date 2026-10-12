# Export and orchestration test cases

Under test: workflow `06_export_reporting` (with macro `Export_View`) and the orchestrator
`03_Alteryx/workflows/00_orchestrator.yxmd` (with `01_Setup/sql/10_orchestration.sql`). Design:
`07_Docs/steps/06_reporting_and_export.md` and `07_orchestration.md`. Start state: `reset_pipeline_state.sql` run, source files staged.

| ID | Case | Expected outcome | How to verify |
|---|---|---|---|
| EXP-TC01 | Every `rpt` view exported | One `04_Prepared/rpt_<View>.csv` per view in `sys.views` (19), UTF-8 with a header row | List `04_Prepared/`; compare with `SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('rpt')` |
| EXP-TC02 | Export reconciles | For every file: data rows in the CSV = `RowCount` in `_manifest.csv` = `COUNT(*)` of the view; 06 raises an error on any mismatch | Count CSV lines minus header; compare with the manifest and the views |
| EXP-TC03 | Manifest is traceable | `_manifest.csv` has FileName, SourceView, RowCount, BatchId, GeneratedAt; BatchId is the run's `06_export_reporting_<stamp>` | Open `_manifest.csv`; match BatchId to `audit.Audit_ETLRunLog` |
| ORC-TC01 | Full run in dependency order | All 8 containers run; stages 01, 02, 03, 04, 04b, 05, 06 each log Succeeded; the warehouse matches the stage-by-stage baseline | `audit.vw_PipelineRun` for the run; `check_dw_load.sql`, `check_rpt_views.sql` |
| ORC-TC02 | One run identifier | Every stage's `LoadRunId` ends with the same 14-digit stamp (the orchestrator's start) | `audit.vw_PipelineRun` returns one `RunStamp` with 8 workflows |
| ORC-TC03 | Stop on failure | A stage error cancels the run; no later stage starts; the orchestrator does not log Succeeded | Results window; `audit.vw_PipelineRun` shows no rows for later stages |
| ORC-TC04 | Stuck-run guard | After a failed or cancelled run, the next run refuses in pre-flight and names the stuck workflows | Run again; expect "Pre-flight failed: A previous run is stuck in Started (...)" |
| ORC-TC05 | Recovery | `audit.usp_AbandonStuckRuns` with a reason clears the guard; without a reason it raises error 50020 | `audit.vw_StuckRun` empty afterwards; the next run passes pre-flight |
| ORC-TC06 | Run summary | `02_SampleData/_runtime/run_summary_latest.csv` lists this run's 7 stages, all Succeeded | Open the file |
