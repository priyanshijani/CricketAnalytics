# Warehouse load test cases

Workflow under test: `05_transform_load.yxmc` with `dw.usp_PublishWarehouse`
(`01_Setup/sql/08_warehouse_load_schema.sql`). Build detail: `07_Docs/steps/05_warehouse_load.md`.

Start state: baseline files staged, workflows `01`–`03` run, DQ state cleared, warehouse empty; then `04`
(and `04b`) run so the `stg.*Valid` queue is full.

| ID | Case | Steps | Expected outcome | How to verify |
|---|---|---|---|---|
| DW-TC01 | Initial load | Run 05 | Row counts as in `check_dw_load.sql` section 1 (119 matches, 233 innings, 28,069 balls, 2,046 batting, 1,246 bowling, 1,839 partnerships, 1,673 fall of wicket, 4,424 over rows, 394 bridge rows, 756 rankings, 395 season stats); queue consumed; load tables empty | `check_dw_load.sql` sections 1 and 9 |
| DW-TC02 | Derived facts reconcile with the scorecard | After DW-TC01 | For every innings with ball-by-ball: runs from ball-by-ball, partnerships and over summary equal the innings total; wickets from ball-by-ball, fall of wicket and over summary equal the innings wickets | `check_dw_load.sql` section 2 returns 0 rows |
| DW-TC03 | Dim_Team Type-2 SCD | After DW-TC01 | DEL has two versions (Delhi Falcons to 2024-04-08, Delhi Comets from 2024-04-09, current); 2023 matches resolve to the Falcons key, 2024–2025 to the Comets key; bridge rows follow the same versions | `check_dw_load.sql` sections 4–5 |
| DW-TC04 | Held matches carry no ball-by-ball | After DW-TC01 | M0001, M0006, M0008: 0 balls and no derived ball-level facts; status columns set on `Fact_MatchResult` | `check_dw_load.sql` sections 6–7 |
| DW-TC05 | Partnerships from striker-only data | After DW-TC01 | 1,839 partnerships; 103 with `Player2Key` NULL (partner never faced a ball); identical results on the AMP and E1 engines | `check_dw_load.sql` section 8 |
| DW-TC06 | Idempotent: re-run with nothing new | Run 05 again | Every warehouse table unchanged (row count and checksum); no rows affected in the publish log | Compare a checksum of each table before and after |
| DW-TC07 | Idempotent: full re-validation and reload | Clear DQ state, run 04 then 05 | Warehouse identical to DW-TC01; `MatchKey` / `TeamKey` / `PlayerKey` unchanged (rows updated in place, not re-inserted) | Checksum comparison; publish log shows `Updated`, not `Inserted`, for matches and innings |
| DW-TC08 | Corrected and new match | Stage `demo_changes/corrected_files/M0031.json` and `demo_changes/new_matches/M0121.json`; run 02, 04, 05 | M0031 keeps its `MatchKey`; winner and innings updated; its scorecard no longer agrees with the existing ball-by-ball, so the consistency rule holds it and the publish removes M0031's ball-level facts (`BallByBallStatus = Held`); M0121 inserted with a new `MatchKey` | `Fact_MatchResult` for both matches; latest `audit.Audit_PublishLog` |
| DW-TC09 | Atomic publish | Force a publish error (for example a duplicate key) | Nothing in `dw` changes; the queue is not consumed; the run fails with the SQL error | `SELECT COUNT(*) FROM dw.Fact_MatchResult` before and after |
| DW-TC10 | Partly written load is refused | `stg.LoadReady_*` row counts differ from `stg.LoadReady_Control.LoadRowsWritten` | Publish aborts with error 50010 | Run `EXEC dw.usp_PublishWarehouse` against a hand-edited load |
