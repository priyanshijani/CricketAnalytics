# 03_Alteryx/workflows

**Run the pipeline:** open `00_orchestrator.yxmd` in Designer and run it (AMP engine). It runs:

0. **Pre-flight** - database reachable; no run stuck in `Started` (`audit.vw_StuckRun`); `config.Parameter`,
   active DQ rules and the calendar present; files waiting in `02_SampleData/_runtime/inbound`. Any failure
   stops the run with one message saying what to fix.
1. `01_ingest_sql.yxmc` — master data from `CricketSource`.
2. `02_ingest_json.yxmc` — nested match JSON from the runtime inbound folder.
3. `03_ingest_csv.yxmc` — ball-by-ball, rankings and historical CSVs.
4. `04_dq_validation.yxmc` — the DQ gate: rules from `config.DQRule` run inside SQL Server (`DQ_RunRules`),
   only over new or changed files; violations to `audit.Audit_DQException`; passing rows to `stg.*Valid`.
5. `04b_dq_feedback.yxmc` — quality scores per run and one open-issues report per owner.
6. `05_transform_load.yxmc` — every dimension and fact derived in Alteryx, published by
   `dw.usp_PublishWarehouse` in one transaction. Idempotent.
7. `06_export_reporting.yxmc` — every `rpt` view to `04_Prepared/rpt_<View>.csv` plus `_manifest.csv`.
8. **Run summary** - this run's stages from `audit.vw_PipelineRun`, written to
   `02_SampleData/_runtime/run_summary_latest.csv`.

Each stage sits in its own **Control Container**, which starts only when the previous stage's container
finished without an error message; the workflow also cancels on any error. Every stage's `LoadRunId` is
`<stage>_<yyyymmddHHMMSS>` with the timestamp of the orchestrator's start, so one run is traceable across
every table.

**Each stage is a standard macro (`.yxmc`) and that file is its only copy** - the orchestrator embeds it, and
you can also open and run any stage on its own in Designer. Do not keep or save a `.yxmd` copy of a stage:
two editable copies drift (a Designer save of an older copy has already reverted changes twice in this project).

All paths are relative to this folder (`%Engine.WorkflowDirectory%`); folder names come from
`config.Parameter`, not hardcoded values. If a run fails, see "Troubleshooting" in
`07_Docs/deployment.md`.
