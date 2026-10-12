# Data-Quality Approach

How data-quality issues are detected, handled and traced. Expands section 7 of `00_Project_Plan.md`.
Build detail is in `07_Docs/steps/04_data_quality.md`; test cases are in
`06_Tests/test_cases/dq_test_cases.md`.

## 1. Principles

- **Nothing is dropped silently.** Every staged row ends up in a `stg.*Valid` table or is logged in
  `audit.Audit_DQException` with the rule it broke. Each run proves it: rows in = valid + rejected, or the
  run stops with an error.
- **Rules are data, not code.** Every rule is a row in `config.DQRule`. Adding or changing a rule changes no
  workflow.
- **Validate once.** Only files whose content has not been processed before are validated; re-runs are cheap
  and idempotent.
- **Fix at the source.** The pipeline never patches data. Owners correct and re-send; a corrected file is
  picked up as `Reprocessed` and its issues resolve automatically.
- **Present complete matches only.** The match is the unit of acceptance for ball-by-ball, so dashboards
  never show a half-loaded match.

## 2. Foundations

| Element | Source |
|---|---|
| DQ dimensions (completeness, validity, uniqueness, integrity, consistency, conformity) | DAMA-UK, *The Six Primary Dimensions for Data Quality Assessment* (2013); Wang & Strong, *Beyond Accuracy* (1996); ISO/IEC 25012 |
| Rule catalogue and exception log | Kimball & Caserta, *The Data Warehouse ETL Toolkit* (2004): data-quality screens and the error-event schema |
| Rules as declarative metadata evaluated by an engine | The approach of Amazon Deequ (Schelter et al., VLDB 2018), Great Expectations and dbt tests |
| Validate before publish | Write–Audit–Publish; the bronze-to-silver step of a medallion architecture |
| Define → measure → analyse → improve | Wang, *A Product Perspective on Total Data Quality Management* (1998) |
| Rows in = valid + rejected | Balancing controls from financial auditing |

## 3. Flow

```
stg.*Raw (workflows 01-03)
   │
   ▼  04_dq_validation
   ├─ Rule engine: config.vw_DQRuleSql → DQ_RunRules batch macro runs each SQL rule inside SQL Server,
   │               only over files whose hash is not in audit.Audit_FileControl
   ├─ Workflow rules: parent-match cascades, CSV header check
   ├─ Match unit of acceptance: a failing delivery or a scorecard mismatch holds the whole match's ball-by-ball
   ├─► audit.Audit_DQException   every violation (rule, row, raw value, action)
   ├─► stg.*Valid                rows with no Rejected violation, typed (queue for workflow 05)
   ├─► stg.MatchCompletenessValid  per match: InningsStatus, BallByBallStatus
   ├─► audit.Audit_FileControl   per file: New / Reprocessed / Duplicate / Rejected
   └─► audit.DQRunEntity         rows checked / valid / rejected per entity
   │
   ▼  04b_dq_feedback
   ├─► audit.DQRunScore          score per run, entity and dimension
   └─► 02_SampleData/_runtime/dq_reports/   open issues per owner, root-cause summary, scorecard
```

## 4. Define - the rules

`config.DQEntity` has one row per entity (Match, Innings, Delivery, PlayerRanking, HistoricalStats, Player,
File): its staging table, natural-key expression, expected CSV header and owner.

`config.DQRule` has 43 rules: 39 evaluated in SQL, 4 by the workflow. Each rule has:

| Column | Meaning |
|---|---|
| `RulePredicate` | T-SQL condition over alias `r` (the staging row) that is true for a bad row |
| `RawValueExpr` | The offending value written to the exception |
| `Dimension` | Completeness, Validity, Uniqueness, Integrity, Consistency or Conformity |
| `ActionTaken` | `Rejected` (row kept out of `stg.*Valid`), `Flagged` (logged, row loads), `Defaulted` (logged, value loaded as NULL) |
| `HoldsBallByBall` | 1 = a violation holds back every delivery of the affected match |
| `ScopePredicate` | Overrides the default incremental scope (the consistency rules also run when only the deliveries file is new) |
| `RootCauseCategory`, `RemediationHint` | Why this class of issue happens, and what the owner should do |
| `IsActive` | Switches the rule on or off |

`config.vw_DQRuleSql` turns each active SQL rule into one `SELECT` with a fixed output
(`RuleId, StgRowId, NaturalKey, SourceFile, RawValue`), adding the incremental filter. Any statement can be
pasted into SSMS to see exactly what a rule catches.

The four workflow-evaluated rules depend on this run's own results or on reading the file:
`parent_match_rejected`, `orphan_match_reference`, `match_ballbyball_held` and `schema_mismatch`. Their
action and on/off switch still come from `config.DQRule`.

To change rules, edit the `MERGE` in `01_Setup/sql/06_dq_metadata_schema.sql` and re-run it (the script is
the source of truth).

## 5. Measure - the gate (workflow 04)

**Scope.** A file is validated once: when its content hash is not yet in `audit.Audit_FileControl`. The
`Players` master is checked every run. A file processed before is logged `Duplicate` and skipped.

**Cross-source consistency.** Each JSON innings total (runs and wickets) is compared with the sum of its
deliveries. This independently catches the planted 11-wicket innings (DQ04) and the −1 run (DQ06).

**Match unit of acceptance.** When any delivery of a match fails, or the scorecard and ball-by-ball disagree,
or one of its innings is rejected, all of that match's in-scope deliveries are held (`match_ballbyball_held`), and the match is marked
`BallByBallStatus = 'Held'` so workflow 05 also removes any ball-by-ball loaded earlier. A rejected innings
marks the match `InningsStatus = 'Incomplete'`. When the sources disagree, ball-by-ball is held whichever
source is wrong - a deliberately conservative policy.

**File status.** `New`; `Reprocessed` (same file name accepted before, new content); `Duplicate` (same
content earlier in the batch, or already processed); `Rejected` (match header or CSV schema failed).

**Contract with workflow 05.** The file-based `stg.*Valid` tables are a queue (load, then delete what was
loaded); take the latest `LoadRunId` per match; apply `stg.MatchCompletenessValid`; `stg.PlayersValid` is the
full master each run.

## 6. Analyse and improve - the feedback loop (workflow 04b)

| Output | Use |
|---|---|
| `audit.DQRunScore` / `audit.vw_DQScoreTrend` | Score per run, entity and dimension: % of checked rows with no violation; `Overall` = % accepted. Tracks quality over time. |
| `audit.vw_DQIssue` | One row per distinct issue with derived lifecycle: **Open** while the latest run that validated its source still raises it, **Resolved** once a later run validates that source without it. First seen, runs seen, age, owner, root cause, remediation. |
| `audit.vw_DQRootCause` | Open issues by root cause, owner and rule - the Pareto view. |
| `dq_open_issues_<OwnerCode>.csv` | One file per owner with the remediation per issue; owners with nothing open get a "No open issues" row. |
| `dq_root_cause_summary.csv`, `dq_scorecard_latest_run.csv` | Root-cause Pareto and the run's scorecard. |

Owners: match data provider (JSON), ball-by-ball provider, player statistics provider, master data steward,
CSV file provider.

## 7. Planted issues and outcomes

| Issue | Rule(s) | Outcome |
|---|---|---|
| DQ01 missing DOB | `missing_date_of_birth` | Flagged; loads with NULL DOB |
| DQ02 future DOB | `future_date_of_birth` | Defaulted; DOB loaded as NULL so the player's deliveries still load |
| DQ03 innings missing runs | `missing_required_field` | Innings rejected; match loads, marked Incomplete; its ball-by-ball held |
| DQ04 11 wickets | `wickets_exceed_ten`, `innings_wickets_mismatch` | Innings rejected; match's ball-by-ball held |
| DQ05 team `XYZ` | `orphan_team_reference`, `winner_not_participant` | Match, its innings and 249 deliveries rejected |
| DQ06 negative runs | `negative_runs`, `innings_runs_mismatch` | Delivery rejected; match's ball-by-ball held |
| DQ07 unknown player | `orphan_player_reference` | Delivery and historical-stats row rejected; match's ball-by-ball held |
| DQ08 duplicate file | `duplicate_file` | Second file `Duplicate`; first loads |
| DQ09 upper-case name | — | Not checked: names come from the master, `player_name` is not staged |
| DQ10 dd/mm/yyyy dates | `invalid_date` (only if unparseable) | Parsed correctly; not an error |
| DQ11 broken JSON | `missing_required_field` | File `Rejected` |
| DQ12 no match_id | `missing_match_identity` | File `Rejected` |
| DQ13 wrong CSV columns | `schema_mismatch` | File `Rejected` |

Baseline result: 30,758 rows in, 29,724 valid, 1,034 rejected; 1,076 exceptions; 4 matches not fully complete.

Found after the fact: the warehouse reconciliation in `06_Tests/sql/check_dw_load.sql` exposed batsmen dismissed
twice in one innings (not planted). It became rule `batsman_dismissed_twice` (Flagged) - TDQM's improve step
turning a newly discovered defect into a permanent check.

## 8. Known limitations

The three structural limitations - no dataset-level or statistical checks, unversioned rules executed as
dynamic SQL, and a feedback loop that stops at report files - are set out with their production remedies in
`00_Project_Plan.md`, section 10. In addition:

- **Owner reports include consequences.** Cascaded issues (`match_ballbyball_held`, `orphan_match_reference`,
  `parent_match_rejected`) are listed under the owner of the held entity, so the ball-by-ball provider's file
  shows 764 issues of which 2 are its own. Filtering "Upstream dependency" rows out of the owner files (or
  rolling them up per match) would leave each owner only what they can act on.
- **Content already processed is never re-validated.** If master data is fixed (for example team `XYZ` added),
  the rejected file stays rejected until it is re-sent or its `Audit_FileControl` rows are deleted.
- **Rejected files are not moved** to the runtime `error` folder (`config.Parameter.ErrorFolderName`), and
  accepted files are not archived; until they are, every rerun logs unchanged files as `Duplicate`.
- **CSV routing is by file name.** `03` reads a CSV only if its name starts with `deliveries`, `player_rankings` or
  `historical_stats`; any other CSV is rejected by `04` as `schema_mismatch`, never silently loaded.
