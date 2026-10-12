# 02_SampleData

Step 2: generate and load the sample dataset.

- `generator/` — the Python script that produces everything in `source/`.
- `source/` — canonical sample inputs. Committed, and never modified by the ETL.
- `stage_source_files.bat` / `stage_demo_change.bat` — copy files from `source/` into the runtime
  inbound folder to trigger a pipeline run.
- `_runtime/` — gitignored working area the ETL actually reads from and writes to (created on first
  staging run; not committed).

`source/` is committed because it's part of the "source data to reproduce the solution" deliverable.
