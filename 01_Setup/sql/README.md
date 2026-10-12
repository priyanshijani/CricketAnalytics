# 01_Setup/sql

Schema creation scripts, run in numeric order by `../setup_database.bat`:

1. `00_create_databases.sql` — creates `CricketSource` and `CricketDW`.
2. `01_source_schema.sql` — `CricketSource`: Teams, Players, Venues.
3. `02_warehouse_schema.sql` — `CricketDW`: dimensions (including the Type-2 `Dim_Team`), the
   player/team/season bridge, and every fact table.
4. `03_audit_control_schema.sql` — `CricketDW`: file-control, DQ exception, and ETL run-log tables,
   plus the `config.Parameter` table.
5. `04_populate_dim_date.sql` — seeds `dw.Dim_Date` with a calendar spine (2022-2026). Reference data,
   not sourced from JSON/CSV/SQL, so it's built here rather than by an Alteryx workflow.
6. `05_validated_staging_schema.sql` — `CricketDW`: the `stg.*Valid` tables workflow `04_dq_validation`
   writes (rows that passed the DQ gate, typed), plus `stg.MatchCompletenessValid`. Workflow `05` reads only these.
7. `06_dq_metadata_schema.sql` — `CricketDW`: the metadata-driven DQ framework - `config.DQEntity`,
   `config.DQRule` (every rule, its SQL predicate and ActionTaken), `config.vw_DQRuleSql`, the
   incremental-scope views (`stg.vw_DQPendingFile`, `stg.vw_DQSkippedFile`, `stg.vw_DQPriorAcceptedMatch`),
   and a `StgRowId` identity on each validated staging table. Rules are edited here and re-applied.
8. `07_dq_feedback_schema.sql` — `CricketDW`: the DQ feedback loop - `audit.DQRunEntity` (rows checked per
   run, written by `04`), `audit.DQRunScore` (scores, written by `04b`), `RuleId`/`StgRowId` on
   `Audit_DQException`, and the `audit.vw_DQIssue` (lifecycle), `vw_DQRootCause` and `vw_DQScoreTrend` views.
9. `08_warehouse_load_schema.sql` — `CricketDW`: the warehouse load - team names on `stg.MatchRaw` /
   `MatchValid` (source of the `Dim_Team` Type-2 history), nullable `Fact_Partnership.Player2Key`, completeness
   columns on `Fact_MatchResult`, `dw.Fact_PlayerSeasonStats`, the `stg.LoadReady_*` tables workflow `05` writes,
   `audit.Audit_PublishLog`, and `dw.usp_PublishWarehouse` (one-transaction publish).
10. `09_security.sql` — the three least-privilege SQL logins and their roles (`source_reader`, `etl_writer`,
    `report_reader`). Passwords come from `config/local.config` as sqlcmd variables; `setup_database.bat`
    skips this script with a warning if they are not set. See `07_Docs/security.md`.

11. `10_orchestration.sql` — `audit.vw_StuckRun` (the orchestrator's concurrency guard),
    `audit.usp_AbandonStuckRuns` (record a decision to abandon a failed run) and `audit.vw_PipelineRun` (one
    row per run per stage, for the run summary).

`setup_database.bat` also applies `03_Alteryx/reporting_views/rpt_reporting_views.sql` (the `rpt` reporting
layer) after these scripts.

Each script is idempotent (safe to re-run) and contains no environment-specific values.
