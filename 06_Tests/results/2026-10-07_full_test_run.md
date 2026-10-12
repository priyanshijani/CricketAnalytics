# Full SQL test run - 2026-10-07

`06_Tests/run_sql_tests.bat` against SQL Server 2019 Express (15.0.2000.5), after orchestrator run `20261007`
(all 7 stages Succeeded). Cases: `../test_cases/sql_quality_test_cases.md`, `../test_cases/rpt_security_test_cases.md`.
Requirement coverage: `../traceability_matrix.md`.

| Script | Checks | Pass | Fail |
|---|---|---|---|
| `check_reconciliation.sql` | 19 | 19 | 0 |
| `check_business_rules.sql` | 25 | 23 | 2 |
| `check_referential_integrity.sql` | 15 | 15 | 0 |
| `check_rpt_views.sql` | 30 | 30 | 0 |
| `check_security.sql` | 19 | 19 | 0 |
| **Total** | **108** | **106** | **2** |

Highlights: source -> snapshot -> dimension counts equal (8 teams, 152 players, 8 venues); every staged file
validated and every file / DQ run balanced (read = loaded + rejected); every staged match either loaded or
explained by an exception; every innings reconciles with its ball-by-ball, partnerships, over summary and fall of
wickets; the last export wrote exactly the rows the rpt views hold (18,524 after the row-outcome view was added); the Data Quality dashboard row outcomes equal the DQ gate's own counts; all 42 foreign keys enabled, trusted
and violation-free; every exception, warehouse match and run traceable to its rule, file and run-log entry.

## Failures - source-data defects

| Check | Actual | Meaning |
|---|---|---|
| BR06 Bowler with more than 4 overs in an innings | 13 spells (largest: 12 overs, M0115 innings 1) | The sample generator breaks the T20 limit of 4 overs per bowler. No DQ rule checks it, so these spells are in the warehouse and in bowling figures. |
| BR12 Chase that continued after the target was passed | 42 of 112 decided matches (e.g. M0120: target 154, DEL finished 180/8) | The generator lets a chasing innings run on. Totals, run rates and partnerships of those innings include runs that could not have been scored. |

Both are real data-quality findings the DQ gate does not yet detect: the improve step of the DQ cycle is to add
them as rules (flag, so the matches stay in the analysis with a warning).

## Performance (PERF-TC01, PERF-TC02) - `check_performance.sql`

| Measurement | Rows | Average |
|---|---|---|
| Runs per over, computed live from `Fact_BallByBall` | 28,069 | 3.6 ms |
| Runs per over, read from `Agg_OverSummary` (pre-aggregated) | 4,424 | 0.4 ms (9x faster) |
| Full read of all 19 rpt views (workflow 06 workload) | 18,490 | 176 ms in total; slowest `rpt.PlayerPhase` 44 ms |

At this data volume there is no bottleneck; the pre-aggregated over summary and the indexes on the fact keys are
what keep the per-over and per-match views cheap as the ball-by-ball volume grows.
