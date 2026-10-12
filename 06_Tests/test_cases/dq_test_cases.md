# Data-quality test cases

Covers the requirement "Detect and handle data-quality issues, with traceability" in the traceability
matrix (`07_Docs/00_Project_Plan.md`, section 2). Workflows under test: `04_dq_validation.yxmc` and
`04b_dq_feedback.yxmc`. Design: `07_Docs/dq_approach.md`.

Start state for every case: baseline files staged (`02_SampleData/stage_source_files.bat`), workflows
`01`–`03` run, and DQ state cleared (`06_Tests/sql/reset_pipeline_state.sql`) unless stated.

| ID | Case | Steps | Expected outcome | How to verify |
|---|---|---|---|---|
| DQ-TC01 | Baseline: every planted issue detected | Run 04, then 04b | 30,758 rows in = 29,724 valid + 1,034 rejected; 1,076 exceptions; 129 file-control rows (124 New, 1 Duplicate, 4 Rejected); every planted issue DQ01–DQ08 and DQ11–DQ13 has its exception | `check_dq_run.sql` sections 1–5 (section 5 returns 0 rows) |
| DQ-TC02 | Rejected rows never reach the Valid tables | After DQ-TC01 | M0013 absent from `stg.MatchValid`; no ball-by-ball of a held match in `stg.BallByBallValid`; no future DOB in `stg.PlayersValid` | `check_dq_run.sql` section 7 returns 0 rows |
| DQ-TC03 | Match is the unit of acceptance for ball-by-ball | After DQ-TC01 | M0001 (one negative-runs delivery, one unknown player), M0006 (rejected innings) and M0008 (rejected innings, scorecard/ball-by-ball wicket mismatch) have 0 deliveries in `stg.BallByBallValid` and `BallByBallStatus = 'Held'` | `check_dq_run.sql` section 8 |
| DQ-TC04 | Cross-source consistency | After DQ-TC01 | `innings_runs_mismatch` for M0001 innings 1 (167 vs 166) and `innings_wickets_mismatch` for M0008 innings 1 (11 vs 4), both Flagged | `check_dq_run.sql` section 4 |
| DQ-TC05 | Legitimate edge cases are not errors | After DQ-TC01 | Abandoned M0061, no-result M0066, tied M0048 and super-over M0076 are in `stg.MatchValid` with no exception | `SELECT * FROM audit.Audit_DQException WHERE NaturalKey LIKE 'M0061%' OR NaturalKey LIKE 'M0066%' OR NaturalKey LIKE 'M0048%' OR NaturalKey LIKE 'M0076%'` returns 0 rows |
| DQ-TC06 | Rerun with no new files (incremental) | Run 04 again without clearing | Only the players master is checked (152 in); every staged file logged `Duplicate` (128); nothing appended to the file-based Valid tables | Latest `audit.Audit_ETLRunLog` row for 04; `audit.Audit_FileControl` for the latest LoadRunId |
| DQ-TC07 | Corrected and new files (incremental) | After DQ-TC01, stage `demo_changes/corrected_files/M0031.json` and `demo_changes/new_matches/M0121.json`, run 02, then 04 | Only those 2 files are validated; `M0031.json` status `Reprocessed`, `M0121.json` status `New`; both appended to `stg.MatchValid` | `audit.Audit_FileControl` for the latest LoadRunId |
| DQ-TC08 | Issue lifecycle: a fixed file resolves its issue | After DQ-TC01, re-deliver `M0006.json` with innings 2 `runs` filled in (234), run 02, 04, 04b | `M0006.json` `Reprocessed` with 0 rows rejected; its issue `Resolved` in `audit.vw_DQIssue`; `InningsStatus` `Complete`; issue removed from `dq_open_issues_match_data_provider.csv`. Its ball-by-ball stays `Held` until the deliveries file is re-sent (already-processed content is not re-validated) | `SELECT * FROM audit.vw_DQIssue WHERE SourceFile = 'M0006.json'` |
| DQ-TC09 | Quality scores and owner reports | After DQ-TC01 | 29 score rows in `audit.DQRunScore`; 7 files in `02_SampleData/_runtime/dq_reports/` (one per owner, root-cause summary, scorecard) | `check_dq_run.sql` sections 9–10; list the folder |
| DQ-TC10 | Rerun 04b for the same 04 run is safe | Run 04b twice | Still 29 score rows for that LoadRunId (PreSQL deletes before insert); report files overwritten | `SELECT COUNT(*) FROM audit.DQRunScore WHERE LoadRunId = (SELECT MAX(LoadRunId) FROM audit.DQRunEntity)` |
| DQ-TC11 | Rule metadata change needs no workflow change | Set a rule `IsActive = 0` in `config.DQRule` (or change its `ActionTaken`), clear DQ state, run 04 | That rule's exceptions disappear (or change action); restore by re-running `06_dq_metadata_schema.sql` | `check_dq_run.sql` section 4 |
