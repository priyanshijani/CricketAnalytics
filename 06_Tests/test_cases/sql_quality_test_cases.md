# Reconciliation, business-rule, referential-integrity and performance test cases

Under test: the whole data flow, checked in SQL Server. Unlike `dq_test_cases.md` and `dw_test_cases.md` (which
expect the numbers of a first baseline load), these checks are invariants: they must hold after **any**
successful orchestrator run, including runs that add new, corrected or duplicate files.

Run them all with `06_Tests/run_sql_tests.bat` (also runs `check_rpt_views.sql` and `check_security.sql`); each
script can also be opened in SSMS. Every check prints one row ending in PASS or FAIL.

## Reconciliation - `06_Tests/sql/check_reconciliation.sql`

| ID | Check | Expected |
|---|---|---|
| RC01-03 | Teams, players, venues in `CricketSource` = staging snapshots | Equal counts |
| RC04-06 | Staging = dimensions (players, venues, current team versions) | Equal counts |
| RC07 | Staged files not yet through the DQ gate | 0 |
| RC08 | Files where rows read <> rows loaded + rows rejected | 0 |
| RC09 | DQ runs where rows in <> valid + rejected, per entity | 0 |
| RC10 | Staged matches neither in the warehouse nor explained by a match-level exception | 0 |
| RC11 | Warehouse matches with no staged source row | 0 |
| RC12 | Innings not reconciling with ball-by-ball, partnerships, over summary, fall of wickets | 0 |
| RC13-14 | Bowling scorecard exceeding the innings total; batting runs + extras <> innings total | 0 |
| RC15-16 | Warehouse -> rpt views add or lose no rows (team matches, batting runs) | Equal |
| RC17 | Rows exported by the last workflow 06 run = rows in the rpt views | Equal |
| RC18-19 | Data Quality dashboard row outcomes (`rpt.DQRowOutcome`) = the DQ gate's own counts, per run and in the current state | 0 / Equal |

## Business rules - `06_Tests/sql/check_business_rules.sql`

| ID | Rule | Expected violations |
|---|---|---|
| BR01-07 | Cricket scorecard rules: max 10 wickets and 20 overs per innings, max 6 legal balls per over, no negative runs, a batter out at most once (or flagged by the DQ gate), max 4 overs per bowler, fall-of-wicket numbers 1..n | 0 |
| BR08-13 | Match results: two different teams, winner and toss winner are one of them, no winner for no-result / abandoned, margin consistent with the scores, a chase stops once the target is passed, season = year of the match date | 0 |
| BR14-22 | Calculation rules (`07_Docs/business_rules.md`): strike rate and batting average guards, overs notation, economy, win %, fifty / hundred flags, one Won + one Lost per decided match, running win %, held ball-by-ball excluded | 0 |
| BR23-25 | Type-2 team dimension: one current version per team, no overlaps, every match linked to the version valid on its date | 0 |

## Referential integrity - `06_Tests/sql/check_referential_integrity.sql`

| ID | Check | Expected |
|---|---|---|
| RI01-02 | Declared foreign keys enabled and trusted; `DBCC CHECKCONSTRAINTS` finds no violation | 0 |
| RI03-05 | Played matches have innings; loaded ball-by-ball innings have deliveries; every batter-team-season is in the bridge | 0 |
| RI06-07 | rpt rows reference a match in `rpt.Match` and a player in `rpt.Player` | 0 orphans |
| RI08-10 | Tableau picker keys: every charted player / team is in its picker list; match labels unique and start with the MatchId | 0 |
| RI11-14 | Audit lineage: exceptions -> rules and source files; warehouse matches -> file control; every run id -> run log | 0 |
| RI15 | Validated queue and load tables empty after a successful publish | 0 rows |

## Performance - `06_Tests/sql/check_performance.sql` (timings, not PASS/FAIL)

| ID | Check | Expected |
|---|---|---|
| PERF-TC01 | Runs per over from `Agg_OverSummary` vs computed live from ball-by-ball | Pre-aggregated read is faster |
| PERF-TC02 | Full read of every rpt view (the workflow 06 workload) | Total well under the pipeline's run time |
