# Step 2 · Source data

> **Intent:** realistic data in all three required formats, with real-world problems planted on purpose so the
> data-quality handling can be demonstrated, not just claimed.

**Files:** `02_SampleData/generator/generate_sample_data.py`, `02_SampleData/source/`

## What it contains

| Source | Content | Volume |
|---|---|---|
| SQL Server `CricketSource` | Teams, players, venues | 8 / 152 / 8 |
| JSON (`source/json/matches/`) | One nested file per match: teams, toss, result, innings | 120 matches, 3 seasons |
| CSV (`source/csv/`) | Ball by ball, player rankings, historical stats | ~28,000 deliveries |
| Held back (`source/demo_changes/`) | New, corrected, duplicate and malformed files for the Additional Challenge | 4 scenarios |

**Planted issues** (full catalogue: `02_SampleData/source/DATA_QUALITY_ISSUES.md`): missing values, a re-delivered
duplicate file, negative runs, more than 10 wickets in an innings, mixed date formats, inconsistent name casing, an
unknown team code, a broken JSON file, a JSON file without its match ID, a CSV with the wrong columns.

**Valid edge cases** that must *not* be flagged: an abandoned match, a tie, a super over, not-out batters, a team
renamed between seasons (Delhi Falcons → Delhi Comets).

## Why this way

- **Generated, not downloaded:** fictitious teams and players avoid any confusion with real records, and the
  generator documents exactly which defects exist, so every one can be tested.
- **The run reads a copy:** `stage_source_files.bat` copies `source/` into `_runtime/inbound/`; the pipeline
  never modifies the canonical source files.

## Evidence

`06_Tests/test_cases/dq_test_cases.md` lists every planted issue with its expected outcome; all pass
(`06_Tests/results/2026-10-05_dq_validation.md`).
