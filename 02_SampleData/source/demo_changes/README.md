# 02_SampleData/source/demo_changes

The "Additional data" - files held back from the baseline build and pre-staged for the live demo, so
the Additional Challenge has a rehearsed, verifiable outcome rather than an improvised one.

| Folder | File(s) | Expected outcome when staged and the orchestrator is run |
|---|---|---|
| `new_matches/` | `M0121.json`, `deliveries_M0121.csv` | A new match appears (2025, MUM 147/5 v CHE 148/9, Chennai won by 1 wicket): `Fact_MatchResult` gains one row, `Fact_BallByBall` its 236 deliveries, and the dashboards reflect it |
| `corrected_files/` | `M0031.json` | Mumbai's chase is re-scored 134/10 → 168/6, so the result flips (Delhi won by 31 runs → Mumbai won by 4 wickets); the match row is updated in place and its old ball-level facts are held back, since they no longer match the corrected score |
| `duplicate_files/` | `M0051.json` | No change to the warehouse; `Audit_FileControl` logs a `Duplicate` status for this file |
| `malformed_files/` | `M0999_broken.json`, `M0998_missing_identity.json`, `MALFORMED_deliveries_wrong_schema.csv` | All three are quarantined with a logged reason; no other file in the same run is affected |

How workflow `04` reports each one: a new file is `New` in `Audit_FileControl`; a corrected file is
`Reprocessed` (same name, new content - verified with `M0031.json`); a re-sent identical file is `Duplicate`
and not re-validated; a malformed file is `Rejected` with its rule in `Audit_DQException`.

File names matter: workflow `03` routes a CSV by its name prefix (`deliveries`, `player_rankings`,
`historical_stats`). A CSV with any other name is not read by `03` and is rejected by `04` as `schema_mismatch` -
which is how `MALFORMED_deliveries_wrong_schema.csv` is caught. Processed files stay in the inbound folder, so
every unchanged file is logged `Duplicate` on a rerun (by design: identical content is never reprocessed).

To use one: run `02_SampleData/stage_demo_change.bat <category>`, then open
`03_Alteryx/workflows/00_orchestrator.yxmd` in Designer and run it - the same way as any other pipeline run.
