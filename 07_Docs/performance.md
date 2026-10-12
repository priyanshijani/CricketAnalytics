# Performance

What was considered at each layer, what was changed, why, and the measured effect. Measurements:
`06_Tests/sql/check_performance.sql`, results in `06_Tests/results/2026-10-07_full_test_run.md` (SQL Server 2019
Express, ~28,000 deliveries).

| Layer | Consideration | What was done | Why | Effect |
|---|---|---|---|---|
| SQL: ball-level aggregation | Run-rate charts would aggregate 28,069 deliveries on every query | `dw.Agg_OverSummary` (one row per over, 4,424 rows), built once per load | Aggregate once at load, read many times | Runs per over: 3.6 ms → 0.4 ms, **9x faster** (PERF-TC01) |
| SQL: joins and filters | Facts are joined by match, innings and player; dashboards filter by season | Indexes on fact keys (`MatchKey, InningsNo`), match date and season, unique indexes on natural keys | Seek instead of scan as volume grows | Every `rpt` view read in full in **176 ms** in total (PERF-TC02) |
| SQL: reporting views | Views call scalar business-rule functions | Functions kept simple and deterministic; computed decimals cast to fixed precision | SQL Server 2019 inlines scalar UDFs; Hyper accepts numerics only up to precision 18 | Slowest view `rpt.PlayerPhase` 44 ms |
| Alteryx: incremental DQ | Re-validating every file on every run grows with history | Only files whose content hash is new are validated (`stg.vw_DQPendingFile`) | Work scales with what arrived, not with everything ever received | A rerun with no new files re-checks only the master data (152 players); 128 unchanged files are skipped as duplicates |
| Alteryx: data-quality rules | 43 rules over ~30,000 rows | Rules run as set-based SQL inside SQL Server (batch macro `DQ_RunRules`), not row by row in Alteryx | The database engine does set operations best | One query per rule |
| Alteryx: loading | Many tables, each Output tool commits separately | Load tables written in one stream, then one stored-procedure publish | Fewer round trips; all-or-nothing | One transaction per run |
| Alteryx: engine | Large multi-stage run | AMP engine; a Sort placed directly before every order-dependent Multi-Row Formula | AMP is parallel and does not keep record order | Correct partnerships under AMP (verified against E1) |
| Tableau: data source | Tableau Public cannot query a database; live queries would be slow anyway | One `.hyper` extract per reporting view, already at dashboard grain | Columnar engine, no joins at view time | Match centre's queries: 0.19 s in total (Tableau log, 2026-10-08) |
| Tableau: calculations | Heavy row-level logic slows every interaction | Business rules computed in SQL; Tableau only re-aggregates (`SUM()/SUM()`) | Keeps the extract small and calcs cheap | Few, simple calculated fields |
| Tableau: filters | Many quick filters and `Only relevant values` are slow | Four workbook-wide parameters plus parameter and filter actions; selector calcs are booleans | Booleans filter faster than strings; parameters do not query the data | One control drives every page |

## At larger volumes

Real ball-by-ball volumes (millions of rows a season) would move the next steps forward: columnstore indexes on
`Fact_BallByBall`, partitioning by season, incremental (CDC) loads instead of full re-runs, and a Tableau Server
published extract refreshed after each load (`production_architecture.md`).
