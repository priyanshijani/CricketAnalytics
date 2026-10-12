# Data-quality test results - 2026-10-05

Workflows `04_dq_validation.yxmd` and `04b_dq_feedback.yxmd` (Designer 2026.2.0.8, AMP engine), run with
`AlteryxEngineCmd.exe` and in Designer, against the baseline sample data. Cases defined in
`../test_cases/dq_test_cases.md`.

> **Re-baselined later the same day (Phase 3).** A rejected innings now also holds its match's ball-by-ball, and
> rule `batsman_dismissed_twice` was added. The baseline became 30,758 in = 29,724 valid + 1,034 rejected with
> 1,076 exceptions (M0006 now Held). The figures below are as recorded at the time; the current expected values
> are in `../sql/check_dq_run.sql`, and DQ-TC01 was re-run and passed against them (see `2026-10-05_dw_load.md`).

| ID | Result | Actual |
|---|---|---|
| DQ-TC01 | Pass | 30,758 in = 29,983 valid + 775 rejected; 786 exceptions; 129 file-control rows (124 New, 1 Duplicate, 4 Rejected); `check_dq_run.sql` section 5 returned 0 rows. Reproduced in a Designer run. |
| DQ-TC02 | Pass | Section 7 returned 0 rows. |
| DQ-TC03 | Pass | M0001 and M0008: 0 rows in `stg.BallByBallValid`, `BallByBallStatus = 'Held'` (253 and 262 deliveries held). |
| DQ-TC04 | Pass | M0001 innings 1 `scorecard=167 ballbyball=166`; M0008 innings 1 `scorecard=11 ballbyball=4`; both Flagged. |
| DQ-TC05 | Pass | M0061, M0066, M0048, M0076 accepted with no exception. |
| DQ-TC06 | Pass | 152 rows in (players master only); 128 files `Duplicate`; 0 rows appended to file-based Valid tables. |
| DQ-TC07 | Pass | 2 files validated: `M0031.json` `Reprocessed` (winner DEL → MUM), `M0121.json` `New`. Inbound restored to baseline afterwards. |
| DQ-TC08 | Pass | `M0006.json` `Reprocessed`, 3 read / 3 loaded / 0 rejected; issue `Resolved`; completeness `Complete`; Innings score for that run 100%. Inbound restored afterwards. |
| DQ-TC09 | Pass | 29 score rows; 7 report files written. |
| DQ-TC10 | Pass | 04b re-run: PreSQL deleted and re-inserted the same 29 rows. |
| DQ-TC11 | Not run | — |

## Defects found and fixed during testing

| Defect | Fix |
|---|---|
| Header check treated every CSV as malformed | Alteryx string literals have no `\n` escape; use `CharFromInt(10)` |
| `DQ_RunRules` macro would not open in Designer | Restored the MacroOutput entry in the macro's question list |
| A rule's raw-value SQL failed for single-column rules | `CONCAT_WS` needs at least three arguments; generated calls now end with `, NULL` |
| M0011 marked innings-incomplete because of its duplicate file | Completeness now matches rejected innings to accepted headers by source file, not match id |
| Scores of exactly 100 failed to insert | `FixedDecimal` size counts the decimal point; widened to 7.2 |

## Observations (not defects)

- The ball-by-ball provider's report has 764 open issues, of which only 2 are its own (negative runs,
  unknown player); 762 are consequences of match-level decisions (`match_ballbyball_held`,
  `orphan_match_reference`). See the known limitation in `07_Docs/dq_approach.md`.
- M0008's ball-by-ball is held although the scorecard (11 wickets) is the source that is wrong. This is the
  documented policy: when the two sources disagree, ball-by-ball is held.
