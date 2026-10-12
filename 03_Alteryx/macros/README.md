# 03_Alteryx/macros

Shared components used by more than one workflow:

- A logging macro that writes consistent `Audit_ETLRunLog` entries (start, success, failure) from every
  workflow.
- `DQ_RunRules.yxmc` — batch macro, the DQ rule engine for workflow `04`. Control input = one row per
  active SQL rule from `config.vw_DQRuleSql`; each iteration runs that rule inside SQL Server and returns
  its violating rows (`RuleId`, `StgRowId`, `NaturalKey`, `SourceFile`, `RawValue`).
- `Read_Deliveries` / `Read_PlayerRankings` / `Read_HistoricalStats.yxmc` — batch macros for workflow
  `03`: read one CSV per iteration and tag its rows with that file's hash.
- `Export_View.yxmc` — batch macro for workflow `06`: exports one `rpt` view per iteration to
  `04_Prepared/rpt_<View>.csv` and returns rows written and the view's own row count.

The orchestrator and the seven stage macros live in `../workflows/`, not here: the orchestrator is a
workflow, and each stage macro is that stage's only copy.
