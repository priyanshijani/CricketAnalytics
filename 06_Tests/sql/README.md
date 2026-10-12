# 06_Tests/sql

SQL-level validation scripts: row-count reconciliation against `Audit_FileControl`, business-rule
assertions (strike rate guarded for zero balls faced, wickets per innings capped at ten, match winner
constrained to one of the two competing teams or null), and referential-integrity checks across the
warehouse. Results are recorded in `../results/`.

Scripts:

- `check_dq_run.sql` — checks the latest run of workflows `04_dq_validation` and `04b_dq_feedback`
  against the expected baseline (row reconciliation, file control, every planted issue detected, no
  rejected row in `stg.*Valid`, match completeness, quality scores, issue lifecycle). Its header also holds
  the block that resets the DQ state for a clean re-validation.
- `check_dw_load.sql` — checks the warehouse after workflow `05_transform_load`: row counts, every derived
  fact reconciled with the innings scorecard, `Dim_Team` Type-2 history, the bridge, held matches, partnerships,
  queue consumption and the publish log.
- `reset_pipeline_state.sql` — resets the warehouse, the DQ state and the validated queue so `04` → `04b` →
  `05` run as a fresh baseline (section 2 alone resets only the DQ state). Keeps rules, staged data and run history.
- `reset_full_warehouse.sql` — empties every table any workflow writes, including all run history, so the next
  orchestrator run builds `CricketDW` from nothing. Keeps `config`, `dw.Dim_Date`, views, logins and `CricketSource`.
- `check_rpt_views.sql` — checks the `rpt` reporting layer: grain, totals against the facts, results,
  business-rule edge cases, DQ carried through, SCD2 names. Every row PASS / FAIL.
- `check_security.sql` — impersonates each least-privilege login and proves what it can and cannot do; confirms
  the reporting login can read every `rpt` view; lists server logins.
- `check_reconciliation.sql` — end-to-end counts: source -> staging -> DQ gate -> warehouse -> rpt -> export
  (RC-xx). Holds after any successful run.
- `check_business_rules.sql` — cricket scorecard rules, match-result rules, the calculation rules of
  `07_Docs/business_rules.md`, Type-2 team dimension (BR-xx).
- `check_referential_integrity.sql` — declared foreign keys, undeclared relationships, the keys Tableau's pickers
  rely on, audit lineage (RI-xx).
- `check_performance.sql` — timings: pre-aggregated over summary vs live, full read of every rpt view (PERF-TC01-02).
