# Step 7 · One-click orchestration (Alteryx 00)

> **Intent:** the whole pipeline runs with one click, stops safely on the first failure, and can never run on top
> of a half-finished load.

**File:** `03_Alteryx/workflows/00_orchestrator.yxmd`; guards in `01_Setup/sql/10_orchestration.sql`

![Orchestrator](../images/alteryx_00_orchestrator.png)

## What it does

1. **Pre-flight:** database reachable; no run stuck in `Started` (`audit.vw_StuckRun`); rules, parameters and
   calendar present; files waiting in the inbox. Any failure stops with one message saying what to fix.
2. **Seven stages**, each a standard macro in its own **Control Container**:
   `01 → 02 → 03 → 04 → 04b → 05 → 06`. A gate between containers lets the next stage start only if the previous one
   logged no error.
3. **One run ID:** every stage stamps `"<stage>_" + orchestrator start time`, so one run is traceable across every
   audit table (`audit.vw_PipelineRun`).
4. **Run summary** written to `02_SampleData/_runtime/run_summary_latest.csv`.

## Why this way

- **No command line, no machine paths:** the run lives entirely in Designer, which removes PATH and install-folder
  dependencies on a new PC.
- **Each stage has one copy** (the `.yxmc` the orchestrator embeds), so the orchestrator and a stage opened on its
  own can never drift apart.
- **Fail closed:** a crashed run blocks the next until someone records why it is safe to continue
  (`audit.usp_AbandonStuckRuns`).

## Evidence

A full run from a reset state matches the stage-by-stage numbers; a forced failure stopped the chain; the next run
was refused until the stuck run was abandoned (`06_Tests/results/2026-10-06_export_orchestration.md`).
