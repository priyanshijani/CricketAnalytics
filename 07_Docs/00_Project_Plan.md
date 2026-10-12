# Cricket Analytics Platform — Project Plan

## 1. Overview

An end-to-end BI prototype consolidating cricket data from three source types — a live SQL Server
database, nested JSON match files, and CSV performance files — into a Tableau analytical layer. The
solution covers ingestion, data-quality detection and handling, a conformed star-schema warehouse,
reporting views, and dashboards for Overall, Player, Team, Match, and Trends analysis, plus a rehearsed
procedure for absorbing new or changed source data without manual reporting-data preparation.

Two databases share one SQL Server instance: `CricketSource` (master/reference data, standing in for a
pre-existing system) and `CricketDW` (staging, warehouse, audit/control, and reporting views). Alteryx
performs ingestion, data-quality validation, transformation, and a final export of reporting views to
flat files and Tableau extracts, since the visualization layer (Tableau Public) has no database connectors
and reads those files directly.

## 2. Requirements Traceability Matrix

| Requirement | How It's Satisfied | Repo Artifact | Verification |
|---|---|---|---|
| SQL Server master/reference data (Teams, Players, Venues) | Live source database, seeded once | `01_Setup/sql/01_source_schema.sql`, `02_SampleData/source/sql_server/seed_data.sql` | Row-count checks, `06_Tests/sql/` |
| JSON match data, nested structure | One JSON file per match | `02_SampleData/source/json/matches/*.json`, `match.schema.json` | Schema validation in workflow `02` |
| CSV detailed data (ball-by-ball, performance, rankings, historical) | Four CSV categories | `02_SampleData/source/csv/*` | Conformance checks against `CSV_SCHEMA.md` |
| Alteryx for ETL/data preparation | Six numbered workflows plus the DQ feedback workflow `04b`, shared macros (logging, DQ rule engine, CSV readers, view export), one orchestrator workflow (Control Containers) | `03_Alteryx/workflows/`, `03_Alteryx/macros/` | Run in Designer, `Audit_ETLRunLog` |
| Microsoft SQL Server as the database | `CricketSource` + `CricketDW` | `01_Setup/sql/` | `setup_database.bat` execution |
| Tableau for visualization | Tableau Public workbook on the prepared `.hyper` extracts | `05_Tableau/workbook/` | Opened and checked in Tableau Public; numbers vs SQL (`06_Tests/results/2026-10-07_tableau_workbook.md`) |
| Detect and handle data-quality issues, with traceability | Metadata-driven, incremental DQ gate; exception log to the exact row; quality scores, issue lifecycle and owner reports | `04_dq_validation.yxmc`, `04b_dq_feedback.yxmc`, `config.DQRule`, `Audit_DQException`, `07_Docs/dq_approach.md` | `06_Tests/test_cases/dq_test_cases.md`, `06_Tests/sql/check_dq_run.sql` |
| Reliability, error handling, logging | File-control tracking, transactional loads, run logging | `Audit_FileControl`, `Audit_ETLRunLog` | Workflow-failure test cases |
| Player/Team/Match/Trends analysis | Conformed facts, five dashboards | `Fact_*` tables, `05_Tableau/workbook/` | Dashboard-vs-SQL spot checks |
| Overall/Player/Team/Match dashboard views, usable and interactive | Five-view Tableau workbook plus a DQ status view | `05_Tableau/workbook/` | Usability walkthrough |
| Identify and address performance issues | Indexing, pre-aggregation, extract-based Tableau source | `01_Setup/sql/`, `Agg_OverSummary` | Before/after query timing |
| Authentication, authorization, least privilege | Three scoped SQL logins through database roles | `01_Setup/sql/09_security.sql`, `07_Docs/security.md` | `06_Tests/sql/check_security.sql` |
| Reproducible deployment, no hardcoding | Ordered setup scripts, machine-local config | `01_Setup/`, `config/local.config.example` | Fresh-machine dry run |
| Test coverage: correctness, calculations, flow, dashboard consistency, invalid data | Documented test cases and results; reconciliation, business-rule and referential-integrity suites run by `06_Tests/run_sql_tests.bat` | `06_Tests/` | `06_Tests/traceability_matrix.md` (every requirement -> tests -> latest result) |
| All named deliverables (source data, SQL, Alteryx, Tableau, docs, presentation) | Full repo | Repo root | Deliverable checklist, section 11 below |
| Additional Challenge: new/corrected/duplicate/malformed file handling | Pre-built `demo_changes/` dataset, full re-run via the orchestrator | `02_SampleData/source/demo_changes/`, `stage_demo_change.bat`, `03_Alteryx/macros/` | Rehearsed, documented outcome per file |

## 3. Business Questions

The assignment's own questions — team performance by season, teams with the most wins, consistently
strong players, individual player trends over time, top contributors to team performance, team
performance by opponent, performance by venue, batting and bowling trends — are answered across the
Overall, Player, Team, and Trends dashboards.

Twelve additional questions, each mapped to the dashboard that answers it:

| # | Question | Dashboard |
|---|---|---|
| 1 | Does winning the toss and choosing to bat or field first correlate with winning, by venue? | Match / Trends |
| 2 | How does a team's win rate trend within a season, not just season-over-season? | Team |
| 3 | Which players perform best under pressure — strike rate in the last five overs of an innings? | Player |
| 4 | What is each team's most-used top-order combination, and how does it correlate with results? | Team |
| 5 | How does a player's performance differ home versus away? | Player |
| 6 | Which bowlers are most economical in the powerplay versus the death overs? | Player |
| 7 | What is the head-to-head win/loss record and margin trend between specific team pairs? | Team |
| 8 | Which players are improving or declining year over year? | Player / Trends |
| 9 | Does toss-win correlate with match-win differently by format or venue? | Overall / Trends |
| 10 | Which all-rounders contribute the most combined batting and bowling value per match? | Player |
| 11 | Is the distribution of result types shifting over time — are matches getting closer? | Trends |
| 12 | Which players are most consistent versus most explosive, by variance in match-to-match performance? | Player |

## 4. Architecture and Data Flow

```
CricketSource (live query)          ─┐
02_SampleData/source/json/           ─┼──▶ Alteryx 01-03 (ingest)  ──▶  CricketDW staging
02_SampleData/source/csv/            ─┘        │  file-control / hash logging (JSON, CSV only)
                                                ▼
                                     Alteryx 04 (DQ validation)
                                       completeness · validity · uniqueness
                                       referential integrity · standardization
                                       violations → Audit_DQException, never silently dropped
                                                ▼
                                     Alteryx 05 (transform / load)
                                       surrogate keys · Dim_Team SCD2 · fact grain
                                       per-match transaction: delete + reinsert on correction
                                                ▼
                                     CricketDW warehouse (Dim_*, Fact_*, Bridge_*)
                                                ▼
                                     rpt_* reporting views (03_Alteryx/reporting_views)
                                                ▼
                                     Alteryx 06 (export)  ──▶  04_Prepared/*.csv, *.hyper + _manifest.csv
                                                                        ▼
                                                              Tableau Public workbook
```

**Why two databases.** `CricketSource` stands in for a pre-existing system holding master/reference
data — the assignment's own framing for what SQL Server contains. `CricketDW` is everything built by
this project: staging, the conformed warehouse, audit/control tables, and reporting views. Splitting
them keeps least-privilege access clean: a reader login scoped to `CricketSource`, a writer login
scoped to `CricketDW` staging and warehouse schemas, a reporting login scoped to `CricketDW.rpt`.
A single database with schema-level separation was considered and rejected — it would still work, but
mixing "external source" and "our warehouse" in one database blurs a distinction worth keeping explicit.

**Why SQL Server extraction is a live query, not a file drop.** JSON and CSV are genuinely file-based
deliveries from an external provider. `CricketSource` is a live database Alteryx queries directly on
every run — there is no file to hash, so its audit trail is a timestamped entry in `Audit_ETLRunLog`
rather than a `Audit_FileControl` row.

**Why Tableau reads prepared exports instead of connecting live to SQL Server.** Tableau Public has
no database connectors and accepts only extracts, so workflow `06` writes each view as a `.hyper` extract
(and a CSV) and the workbook reads the extracts through paths relative to itself. Tableau Public has
no database connectors — file-based sources are the only option available, which makes this decision
close to mandatory rather than a pure preference. It also happens to be the stronger design on its own
merits: it removes any database credential requirement from the visualization layer entirely, makes the
handoff portable (a folder, not a working ODBC connection), and `_manifest.csv` gives an inspectable,
traceable link between what SQL Server computed and what a dashboard displays. The tradeoff — no
live/real-time connection — is accepted for a local prototype and documented in section 10.

**Match identity and corrections.** A match's identity is parsed from file content — an embedded match
ID, or a validated team+date+format composite if one is absent. A file missing this identity is treated
as malformed, not silently accepted with a guessed identity. A corrected file for an existing match is
applied in one transaction: the match row is updated in place (its `MatchKey` never changes), innings are
merged and any innings dropped from the correction are removed with their dependants, and the match's
ball-level facts (ball-by-ball, batting, bowling, partnerships, fall of wicket, over summary) are replaced
whenever new ball-by-ball arrives - or removed when the match's ball-by-ball is held because the corrected
scorecard no longer agrees with it. Replacing whole sets rather than merging row by row avoids orphaned rows
when a correction adds or removes players.

**File-control outcomes.** New file → insert. Corrected file (same match identity, new content hash) →
delete and reinsert. Duplicate (identical hash already processed) → skipped, logged. Malformed
(unparsable or schema-violating) → quarantined with a logged reason, and the rest of the batch still
processes — one bad file does not abort a run.

**Workflow-level failure handling**, distinct from data-level issues above: every fact load runs inside
a SQL transaction, so a mid-load failure rolls back rather than leaving the warehouse half-updated.
Every workflow writes a `Started` row to `Audit_ETLRunLog` before doing anything else, and a
`Succeeded`/`Failed` row with an error message when it finishes — a crash is visible as a run stuck on
`Started` or ending `Failed`, never silent. The orchestrator (`00_orchestrator.yxmd`) runs each stage in a
Control Container that starts only if the previous stage logged no error, so a failure halts the chain rather
than running the export against a warehouse that failed to finish loading; its pre-flight refuses to start
while any run is stuck in `Started`.

## 5. Data Model

**Dimensions**

| Table | Grain | Notes |
|---|---|---|
| `Dim_Date` | One row per day | `DateKey` (yyyymmdd int) as PK; includes a season label |
| `Dim_Team` | One row per team version | Type-2 SCD — `EffectiveFrom`/`EffectiveTo`/`IsCurrent` track renames over time |
| `Dim_Player` | One row per player | Natural key, batting/bowling style, role, country, date of birth |
| `Dim_Venue` | One row per venue | Name, city, country, capacity |
| `Dim_MatchFormat` | One row per format | Test, ODI, T20, T10 |
| `Bridge_PlayerTeamSeason` | Player + team + season | Models transfers between seasons without Type-2 churn on `Dim_Player` |

**Facts**

| Table | Grain | Notes |
|---|---|---|
| `Fact_MatchResult` | One row per match | Includes an explicit `ResultMethod` (Normal/Tied/NoResult/Abandoned/SuperOver) and `ManOfMatchPlayerKey` |
| `Fact_Innings` | Team-innings per match | Runs, wickets, overs, extras |
| `Fact_BattingPerformance` | Player per innings | Runs, balls, boundaries, strike rate, dismissal |
| `Fact_BowlingPerformance` | Bowler per innings bowled | Overs, runs conceded, wickets, economy |
| `Fact_BallByBall` | One row per ball, every match | ~29,000 rows at the chosen scale — populated in full, not sampled |
| `Fact_Partnership` | Wicket partnership per innings | Derived from `Fact_BallByBall`; the second partner is NULL when they never faced a ball (ball-by-ball records only the striker) |
| `Fact_FallOfWicket` | Wicket fall per innings | Derived from `Fact_BallByBall` |
| `Agg_OverSummary` | Over per innings | Pre-aggregated for export/dashboard performance |
| `Fact_PlayerRanking` | Player + format + snapshot date | Monthly ranking snapshots |
| `Fact_PlayerSeasonStats` | Player + season + format | Matches, runs and wickets per season from the historical-stats feed |

**Why `Dim_Team` is Type-2 while player-team history uses a bridge table:** these are two different
kinds of change. A team rename is an attribute-history problem — the same entity, a changed name over
time. A player moving between teams across seasons is a time-varying many-to-many relationship, not an
attribute change on the player. Using the matching pattern for each avoids both unnecessary SCD
complexity on `Dim_Player` and an under-modeled team-rename story.

**Configuration, audit, and control**

| Table | Purpose |
|---|---|
| `config.Parameter` | Key/value pipeline settings (folder names, thresholds) — no hardcoded paths in workflow XML |
| `Audit_FileControl` | Per-file hash, status (new/reprocessed/duplicate/rejected), row counts — JSON/CSV sources only |
| `Audit_DQException` | Every data-quality violation: source, entity, rule, raw value, action taken |
| `Audit_ETLRunLog` | Per-workflow run: start/end time, status, row counts, error message |
| `config.DQEntity`, `config.DQRule` | The data-quality rules as metadata: entity, SQL predicate, dimension, action, owner, root cause, remediation |
| `audit.DQRunEntity`, `audit.DQRunScore` | Rows checked per entity per run; quality score per run, entity and DQ dimension |
| `stg.*Valid`, `stg.MatchCompletenessValid` | Rows that passed the DQ gate (queue for workflow `05`), and per-match completeness flags |

Views `audit.vw_DQIssue` (issue lifecycle), `audit.vw_DQRootCause` and `audit.vw_DQScoreTrend` feed the
data-quality status view. Full design: `07_Docs/dq_approach.md`.

## 6. Sample Data Design

**Scale:** approximately three seasons, eight fictitious franchise-style teams (including one mid-history
rename to exercise `Dim_Team`'s Type-2 behavior), 150 fictitious players, 120 matches, ball-by-ball data
for every match, and monthly player-ranking snapshots. Generated by
`02_SampleData/generator/generate_sample_data.py`, which produces both the baseline dataset and the
`demo_changes/` set, along with their schema and data-quality documentation.

**Deliberately injected data-quality issues**, catalogued in full in
`02_SampleData/source/DATA_QUALITY_ISSUES.md`:

- **Missing information:** player date of birth, venue city, scores for abandoned matches.
- **Duplicates:** an identical match JSON delivered twice; a player appearing twice with inconsistent
  name casing between a CSV file and the SQL master.
- **Invalid values:** negative runs, a strike-rate divide-by-zero (zero balls faced), more than ten
  wickets recorded in an innings, a future date of birth.
- **Inconsistent formats:** mixed date formats across CSV files, team-name variants.
- **Incorrect relationships:** a match JSON referencing a team ID absent from the SQL master; a
  performance CSV referencing an unknown player ID.
- **Malformed files:** one JSON file with broken syntax, one CSV with a shifted column count, one JSON
  file missing its match-identity field entirely.

**Legitimate edge cases that must not be flagged as errors:** an abandoned match with a null winner, a
tied match, a super-over match, a not-out batsman, an all-rounder appearing in both batting and bowling
facts, and a match with only summary data and no ball-by-ball file (sparse but valid, not invalid).

**The `demo_changes/` dataset** holds four categories — new matches, corrected files, duplicate files,
malformed files — pre-built and held back from the baseline build specifically to give the Additional
Challenge a rehearsed, verifiable outcome rather than a live improvisation. See
`02_SampleData/source/demo_changes/README.md` for the plug-in procedure.

## 7. Data Quality, Business Rules, and Logging

Data-quality rules are metadata: each is a row in `config.DQRule` with its DQ dimension, a SQL predicate,
and an action (Rejected, Flagged or Defaulted). Alteryx workflow `04_dq_validation` runs them inside SQL
Server through the `DQ_RunRules` batch macro, only over files whose content has not been processed before,
and logs every violation to `Audit_DQException`. The dimensions covered are completeness (required fields
present), validity (values in range - runs non-negative, wickets per innings within
`config.Parameter`), uniqueness (no duplicate files or natural keys), referential integrity (codes resolve
against the master data), consistency (the JSON scorecard agrees with the ball-by-ball totals for runs and
wickets), and conformity (CSV headers match the documented schema). The match is the unit of acceptance for
ball-by-ball: if one delivery of a match fails, or its totals disagree with the scorecard, all of that match's
deliveries are held back and the match is flagged in `stg.MatchCompletenessValid`, so dashboards never show a
half-loaded match. Workflow `04b_dq_feedback` closes the loop: a quality score per run, entity and dimension
(`audit.DQRunScore`), issue lifecycle and root-cause views, and one open-issues report per source owner.
Known limitations of this framework are listed in section 10.

Business calculations — batting average, strike rate (guarded against dividing by zero balls faced),
bowling economy, win percentage — are defined exactly once, in the `rpt_*` reporting views documented in
`07_Docs/business_rules.md`. The Alteryx export, any ad hoc SQL validation, and the Tableau dashboards
all read the same definition, which is the direct mechanism for keeping dashboard numbers consistent
with the underlying data.

Logging operates at two levels: `Audit_FileControl` tracks file-level outcomes for the two file-based
sources, and `Audit_ETLRunLog` tracks workflow-level run status, populated by one shared Alteryx logging
macro so every workflow logs consistently rather than each implementing its own approach.

## 8. Incremental Load and the Additional Challenge

Every pipeline run is a full re-run of workflows `01` through `06`, not a hand-edited patch — this is
what makes the Additional Challenge possible without manual reporting-data preparation. The procedure:

1. Run `02_SampleData/stage_demo_change.bat` and choose a file from `02_SampleData/source/demo_changes/`.
2. The chosen file is copied into the runtime inbound folder.
3. Open `03_Alteryx/workflows/00_orchestrator.yxmd` in Designer and run it — the full pipeline
   processes the new file alongside the existing baseline data, the same way as any other run.
4. Reopen the Tableau workbook (close it before step 3: it locks the `.hyper` extracts that `06` replaces).
5. The dashboard reflects the change: a new match appears, a corrected match's numbers update, a
   duplicate has no effect (logged as skipped), or a malformed file is quarantined (logged with a
   reason) while the rest of the run completes normally.

A small "Data Quality & Load Status" Tableau view, sourced from `Audit_FileControl` and
`Audit_DQException`, makes the outcome demonstrable rather than something asserted from logs alone.

## 9. Security, Performance, Testing, Deployment

**Security.** Three SQL logins, each scoped to one database and one job: a reader with `SELECT` on
`CricketSource` only, a writer with write access to `CricketDW` staging and warehouse schemas only
(it can read the DQ rules in `config` but not change them, since the pipeline executes them), and a
reporting login with `SELECT` and `EXECUTE` on `CricketDW.rpt` only — it cannot see a base table or a column
not deliberately exposed through a view. Passwords live only in the gitignored `config/local.config`.
Implemented in `01_Setup/sql/09_security.sql`, proven by `06_Tests/sql/check_security.sql`. Tableau itself
requires no database credentials at all, since it reads prepared files. A production deployment would
add AD-group-based roles and Tableau Server row-level security via a user-to-team/region filter table —
detailed in `07_Docs/security.md`.

**Performance.** Indexed foreign keys, date keys, and season columns in the warehouse; `Agg_OverSummary`
and the `rpt_*` views so nothing downstream aggregates ball-by-ball data live; bulk-load connections and
early filtering in Alteryx; a flat-file extract source for Tableau chosen over a live connection, with
the tradeoff (no real-time freshness) stated explicitly. Full detail in `07_Docs/performance.md`.

**Testing.** Reconciliation counts across source files, `Audit_FileControl`, `_manifest.csv`, and the
warehouse; business-rule assertions; referential-integrity checks; a full requirement-to-test-case
mapping; dashboard-versus-SQL spot checks. Test cases and results are in `06_Tests/`.

**Deployment.** A new machine needs SQL Server, Alteryx Designer, and Tableau Public already installed.
Two one-time, machine-specific setup steps: `config/local.config` (the SQL instance name, read by the
`.bat` scripts) and two Alteryx Connections, each backed by a Windows ODBC System DSN (read by the
Alteryx workflows themselves). After that, database setup is scripted (`check_prerequisites.bat`, then
`setup_database.bat`) and running the pipeline is a Designer step: stage the source files, then open and
run the orchestrator. Full steps, including verification queries, are in `07_Docs/deployment.md`.

## 10. Prototype Simplifications and Production Alternatives

| Area | Prototype Approach | Production Alternative |
|---|---|---|
| Tableau data source | Reads prepared `.hyper` extracts (relative paths) | Live/extract connection to `CricketDW.rpt` via Tableau Server, its own least-privilege login, row-level security |
| Orchestration | Manual run of one macro inside Designer | Scheduled or event-driven trigger (an Alteryx Server schedule, or a folder-watcher job) |
| Failure visibility | `Audit_ETLRunLog` is queryable but passive | Active alerting on a failed or stuck run |
| Fact correction | Match row updated in place; a match's ball-level facts replaced as a set, inside one publish transaction | At larger scale, more surgical MERGE- or CDC-based updates |
| Access control | Three SQL logins, Windows Authentication | AD-group-based roles, Tableau Server row-level security |
| Scale | ~120 matches, full ball-by-ball (~29K rows) | Real-world ball-by-ball volume would revisit the CSV-export approach |
| Master data governance | `CricketSource` seeded once from a script | An ongoing MDM or source-system update process |

Two of these are constraints of the current tooling rather than choices: the file-based Tableau data
source (Tableau Public has no database connectors) and the absence of server-side row-level security
(Tableau Public has no server or permissions layer at all). The rest — orchestration, alerting,
correction strategy, master-data governance — are deliberate scope decisions for a local
prototype with a live demo, not technical limitations.

### Data-quality framework: known limitations

The DQ gate (`04_dq_validation`, rules in `config.DQRule`) and its feedback loop (`04b_dq_feedback`) follow
established practice: DQ dimensions per DAMA, Kimball's data-quality screens and error-event schema,
declarative rules evaluated by an engine (as in Amazon Deequ or Great Expectations), and Wang's TDQM cycle
of define, measure, analyse and improve. Three limitations remain by design and are stated here rather than
left implicit.

| Limitation | Effect in this prototype | Production remedy |
|---|---|---|
| **Row-level rules only - no dataset-level or statistical checks.** Every rule tests one row (or one innings against its deliveries). Nothing tests a file or batch as a whole: row volume against previous deliveries, value distributions, or arrival time (the *Timeliness* dimension is not measured). | A deliveries file that arrives with half its rows missing, or a season file that silently stops arriving, passes every rule. | Batch-level metrics per file stored in `audit` (row count, sums, null rates, arrival time) with thresholds or anomaly detection against history, as data-observability tools do; a freshness check per source with an expected arrival schedule; a circuit breaker that fails the run when a file's reject rate exceeds a threshold. |
| **Rules are not versioned, and rule SQL is executed dynamically.** `06_dq_metadata_schema.sql` upserts rules in place. `Audit_DQException` records the `RuleId`, but not the rule's predicate as it was at that time. Rule predicates are T-SQL text run by the `DQ_RunRules` macro. | An exception from an old run cannot be reproduced exactly after its rule is edited. Anyone able to write to `config.DQRule` can make the pipeline execute arbitrary SQL with the ETL login's permissions. | Version rules (`RuleVersion` plus effective-from / effective-to, never update in place) and store the version on every exception; review rule changes through source control (the script stays the source of truth) with a separate, tightly granted role for writing `config.DQRule`; or use a constrained rule grammar (column / operator / value) compiled by the engine instead of free SQL. |
| **The feedback loop stops at report files.** `04b_dq_feedback` scores each run (`audit.DQRunScore`), derives issue lifecycle (`audit.vw_DQIssue`: Open / Resolved, first seen, age), rolls up root causes (`audit.vw_DQRootCause`) and writes one open-issues file per owner. Root cause is the rule's assigned category, not a diagnosis of the individual record. | Nobody is notified; owners must look at the files or the Tableau DQ view. There is no acknowledgement, assignment or due date, no turnaround target, and no request to re-validate a rejected file whose master data was later fixed (content already processed is never re-checked). | Push notifications (Alteryx Email tool or a ticketing integration) with an owner and SLA per issue; acknowledgement and waiver records (`config.DQWaiver`); a reprocess-request table that 04 honours; periodic review of the score trend and root-cause Pareto with source owners - the improve step of TDQM, which is a process as much as a tool. |

## 11. Deliverables Checklist

- Working BI solution: SQL Server, Alteryx, Tableau Public, all functioning end to end on a local machine.
- Source data: `02_SampleData/source/` (both the baseline "Actual data" and the `demo_changes/` "Additional data").
- Technical artifacts: `01_Setup/sql/`, `03_Alteryx/` (workflows, macros, reporting views), `05_Tableau/`, `config/`.
- Documentation: this document plus every file listed in `07_Docs/README.md`'s topic table.
- PowerPoint presentation: `07_Docs/presentation/`, outline in section 12 below.

## 12. Presentation and Final Demonstration

**PowerPoint outline**, matching the assignment's required content: business problem, approach, solution
architecture, key technical decisions (SCD2-for-teams versus bridge-for-players, delete-and-reinsert
versus MERGE, prepared-CSV versus live Tableau connection), data processing approach, analytical
solution, key insights (drawn from the actual generated data once built), challenges encountered, and
future improvements (section 10 above).

**Final demonstration checklist**, matching the assignment's required walkthrough: business problem and
approach, solution architecture, data flow, SQL implementation, Alteryx implementation, a live pipeline
run, Tableau dashboards, data-quality handling (an Additional Challenge scenario run live), security
considerations, performance considerations, and deployment approach.

## 13. Build Plan

**Phase 1 — Foundation, data, ingestion, data quality**

1. Prerequisite fixes, `config/local.config`, database and schema creation, Alteryx location and
   command-line smoke test.
2. Sample data generation — baseline and `demo_changes/` datasets, plus schema/catalogue documentation.
3. Seed `CricketSource` from the generated seed script.
4. Alteryx ingestion workflows `01`–`03`, with file-control logging for the file-based sources.
5. Alteryx data-quality workflow `04` (metadata-driven, incremental) and feedback workflow `04b`, tested
   against every planted issue, a rerun, a corrected file and a new file (`06_Tests/results/`).

Definition of done: schema deployed and connectivity verified; sample data generated and documented; all
three source types land in staging with consistent audit logging; every planted data-quality issue
produces its expected exception.

**Phase 2 — Transform/load, reporting, visualization, testing, rehearsal**

1. Alteryx transform/load workflow `05` — dimension conforming, fact loading, idempotency verified.
2. Reporting views (`rpt` schema, business rules as functions) and SQL-level tests; least-privilege logins
   created and proven (`06_Tests/results/2026-10-06_reporting_security.md`).
3. Alteryx export workflow `06`; one-click orchestration assembled (`00_orchestrator.yxmd`, Control
   Containers; `06_Tests/results/2026-10-06_export_orchestration.md`).
4. Tableau workbook — Overview, Team, Player, Player Leaderboards, Match and Trends dashboards plus the
   data-quality status view, on the `.hyper` extracts
   (`06_Tests/results/2026-10-07_tableau_workbook.md`).
5. Full test-case execution.
6. Additional Challenge rehearsal, one pass per `demo_changes/` category.
7. Documentation finalized, presentation built, final end-to-end rehearsal.

Definition of done: warehouse fully populated and idempotent; one-click re-run works; every dashboard
functions against real data; every Additional Challenge scenario rehearsed with a verified outcome; all
deliverables complete.
