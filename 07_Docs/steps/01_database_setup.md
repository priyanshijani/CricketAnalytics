# Step 1 · Database setup

> **Intent:** a reproducible SQL Server foundation, created by script on any PC, with the source system and the
> warehouse kept apart.

**Files:** `01_Setup/setup_database.bat`, `01_Setup/sql/00`–`10_*.sql`, `03_Alteryx/reporting_views/rpt_reporting_views.sql`

## What it does

1. Reads the instance name from `config/local.config` (the only machine-specific value).
2. Creates two databases: **`CricketSource`** (stands in for the organisation's system of record) and
   **`CricketDW`** (everything this project builds).
3. Runs the DDL in order: source tables → warehouse star schema → audit and control → calendar → validated staging
   → data-quality rules → DQ feedback → warehouse publish procedure → orchestration guards.
4. Seeds `CricketSource` (8 teams, 152 players, 8 venues) and creates the 22 `rpt` reporting views.
5. Optionally creates three least-privilege logins (`security.md`).

## Why this way

- **Two databases** mirror reality (an existing source system vs. a warehouse) and let each login be scoped to one.
- **Schemas by purpose** in `CricketDW`: `stg` (landing), `dw` (star), `rpt` (reporting contract), `audit`
  (what happened), `config` (rules and parameters).
- **Idempotent scripts** (`IF OBJECT_ID ... IS NULL`, `CREATE OR ALTER`): re-running setup is safe.
- **Rules and parameters as data** (`config.DQRule`, `config.Parameter`): no folder name or threshold is
  hard-coded in a workflow.

## Evidence

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -Q "SELECT s.name, COUNT(*) FROM CricketDW.sys.tables t JOIN CricketDW.sys.schemas s ON s.schema_id = t.schema_id GROUP BY s.name"
```

Expected: `audit 6, config 3, dw 16, stg 32`. Full schema: [`data_model/`](../data_model/README.md).
