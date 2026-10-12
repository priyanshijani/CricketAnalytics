# Deployment and Run Guide

Everything needed to rebuild and run the solution on a new Windows 10/11 PC, then feed it new data. Follow the
parts in order; each step ends with a check.

| Part | What happens | Time |
|---|---|---|
| [A. Install](#a-install-the-software-once) | SQL Server, sqlcmd, ODBC driver, Alteryx Designer, Tableau Public, Git, Python | 45–60 min (downloads) |
| [B. Configure](#b-configure-this-pc-once) | Clone, one config file, both databases, two ODBC data sources, two Alteryx connections | 15 min |
| [C. Run](#c-run-the-pipeline) | Stage the source files, run one Alteryx workflow, open the Tableau workbook | 10 min |
| [D. Add new data](#d-add-new-or-changed-data) | New / corrected / duplicate / malformed files, or new master data; re-run; see it in Tableau | 5 min per pass |

Nothing in the repository holds a server name, password or absolute path. The machine-specific values live in
two places only: `config/local.config` (created in step B2, gitignored) and the two Alteryx connections (B6).

---

## A. Install the software (once)

| # | Software | Where | Notes |
|---|---|---|---|
| A1 | **SQL Server 2019 or later**, Express (free) or Developer | [microsoft.com/sql-server/sql-server-downloads](https://www.microsoft.com/en-us/sql-server/sql-server-downloads) | Choose **Basic** install. Note the instance name it reports: Express installs as `SQLEXPRESS`, addressed as `localhost\SQLEXPRESS`. Windows authentication is enough. |
| A2 | **sqlcmd** | Installed with SQL Server 2022 / 2025. Only if `sqlcmd -?` fails: `winget install sqlcmd` | Used by the setup scripts. Open a **new** terminal after installing. |
| A3 | **Microsoft ODBC Driver 17 or 18 for SQL Server** | Driver 18 is installed with SQL Server 2025; otherwise `winget install --id Microsoft.msodbcsql.18` | Alteryx connects through it. The scripts use whichever is present. |
| A4 | **Alteryx Designer 2026.2+** (free 30-day trial) | [alteryx.com → Free trial](https://www.alteryx.com/designer-trial) | Create the trial account, install Designer through the Alteryx One app, sign in once. Close other installers while it installs. |
| A5 | **Tableau Public 2026.2+** (free) | [tableau.com/products/public/download](https://www.tableau.com/products/public/download) | Opens the workbook. Saving a workbook locally needs 2026.2.3 or later (not required to review it). |
| A6 | **Git** and **Python 3.10+** | [git-scm.com](https://git-scm.com/download/win), [python.org](https://www.python.org/downloads/) | Python runs the one-time connection relink (B7); standard library only. |
| — | SQL Server Management Studio (optional) | [aka.ms/ssms](https://aka.ms/ssms) | Only to browse the databases; every check below also works with `sqlcmd`. |

**Check:** open a new terminal and run `sqlcmd -?` and `python --version`.

---

## B. Configure this PC (once)

### B1. Clone the repository

```powershell
git clone https://github.com/priyanshijani/CricketAnalytics.git
cd CricketAnalytics
```

Any folder works; every path in the project is relative to the repository.

### B2. Set the SQL Server instance in `config/local.config`

`config/local.config` is the one file that holds this PC's settings; every setup script reads it. Run
**`01_Setup\check_prerequisites.bat`** once: it creates the file from `config/local.config.example`. Open it and
set `SQL_INSTANCE`:

```ini
SQL_INSTANCE=localhost\SQLEXPRESS
```

Not sure of the name? `Get-Service MSSQL*` lists it: `MSSQL$SQLEXPRESS` means `localhost\SQLEXPRESS`;
`MSSQLSERVER` (a default instance) means `localhost`. The three `*_PASSWORD` keys are optional (see B4).

### B3. Check prerequisites

Run **`01_Setup\check_prerequisites.bat`** again. Every line must read `[OK]`.

### B4. Create and seed both databases

Double-click **`01_Setup\setup_database.bat`**. It creates `CricketSource` (the source system: teams, players,
venues) and `CricketDW` (staging, warehouse, audit, reporting views), runs every script in `01_Setup\sql\` in
order, and seeds `CricketSource`. Safe to re-run.

Optional, least privilege: fill `SOURCE_READER_PASSWORD`, `ETL_WRITER_PASSWORD` and `RPT_READER_PASSWORD` in
`config/local.config` first (avoid quotes, `%`, `!`, `^`, `&`, `|`, `<`, `>`, `=`), and the script also creates the
three scoped logins described in `security.md`. Without them it skips that step with a warning.

**Check** (replace the instance name with yours):

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -Q "SELECT (SELECT COUNT(*) FROM CricketSource.dbo.Teams) AS Teams, (SELECT COUNT(*) FROM CricketSource.dbo.Players) AS Players, (SELECT COUNT(*) FROM CricketSource.dbo.Venues) AS Venues"
```

Expected: `8  152  8`.

### B5. Create the two ODBC data sources

Right-click **`01_Setup\create_odbc_dsns.bat`** → **Run as administrator**. It creates the 64-bit System DSNs
`CricketSource_DSN` and `CricketDW_DSN` (ODBC Driver 17, Windows authentication, each with its default database)
and checks that each one saved its database.

### B6. Create the two Alteryx connections

In Alteryx Designer open the **Connections** panel (File → Manage Connections) and choose **New Connection**
twice, technology **Microsoft SQL Server ODBC**:

| Field | Connection 1 | Connection 2 |
|---|---|---|
| Data Source Name | `CricketSource_DataSource` | `CricketDW_DataSource` |
| ODBC DSN | `CricketSource_DSN` | `CricketDW_DSN` |
| Connection name | `CricketSource_DB` | `CricketDW_DB` |
| Authentication | **No Credentials** (the DSN uses Windows authentication) | **No Credentials** |

Why a manual step: Alteryx Designer 2026.2 runs in *DCM Only* mode by default, so tools may use only connections saved
in Designer's own (encrypted) store, which no script can safely create. Each connection only names a DSN from B5, so
no server name or password is typed here: the instance still comes from `config/local.config`.

Create each with **New / Add**; never rename one connection into the other. **Test Connection**, save, then
**close Designer**.

### B7. Point the workflows at these connections

```powershell
python 03_Alteryx\relink_connections.py
```

Designer stores a connection inside each tool by an ID that is unique to the machine where the connection was
created. This script reads the IDs of the two connections you just made (read-only) and writes them into every
workflow and macro. It changes nothing else, and running it again is harmless.

**Check:** the script prints `[OK]` for both connections and ends with `11 of 14 workflow / macro files relinked`.

---

## C. Run the pipeline

### C1. Stage the source files

Double-click **`02_SampleData\stage_source_files.bat`**. It copies the baseline JSON and CSV files from
`02_SampleData\source\` into the pipeline's inbox, `02_SampleData\_runtime\inbound\`.

### C2. Run the orchestrator

Close Tableau (an open workbook locks the extracts). Open **`03_Alteryx\workflows\00_orchestrator.yxmd`** in
Designer and press **Run** (Ctrl+R). It runs pre-flight checks, then every stage in order, each starting only if
the previous one finished without an error:

`01 SQL master data → 02 JSON matches → 03 CSV files → 04 data-quality gate → 04b DQ feedback → 05 warehouse load → 06 export`

It takes a few minutes. Close other applications first if the PC has little free memory.

**Check:** the Results window ends without errors, and `02_SampleData\_runtime\run_summary_latest.csv` lists every
stage as `Succeeded`. In SQL:

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -Q "SELECT COUNT(*) AS Matches FROM CricketDW.rpt.Match"
```

Expected after the baseline run: `119`. The baseline has 120 matches; `M0013` is rejected on purpose (it
references team `XYZ`, which the master data does not know) and is listed on the Data Quality dashboard. `04_Prepared\_manifest.csv`
lists every export with its row count and run ID.

### C3. Open the dashboards

Open **`05_Tableau\workbook\CricketAnalytics.twb`** in Tableau Public. It reads the `.hyper` extracts in
`04_Prepared\` through paths relative to itself, so it needs no connection setup; it always shows the last
pipeline run. Start with **Overview**, or the **Season Story** tab for a guided walkthrough.

### C4. Optional: run the test suite

Double-click **`06_Tests\run_sql_tests.bat`** (108 checks; results in `06_Tests\results\`). What each check proves
is in `06_Tests\traceability_matrix.md`.

---

## D. Add new or changed data

Every pass is the same three moves: **put the data in place → run the orchestrator (C2) → reopen the workbook
(C3)**. Nothing in the reporting layer is edited by hand.

### D1. Ready-made scenarios

```bat
02_SampleData\stage_demo_change.bat new_matches
```

| Scenario | Files | What you should see |
|---|---|---|
| `new_matches` | `M0121.json`, `deliveries_M0121.csv` | Matches 119 → 120; Chennai Kings top the 2025 table; M0121 in the Match centre with its run worm |
| `corrected_files` | `M0031.json` (new content, same match) | M0031 flips from "Delhi won by 31 runs" to "Mumbai won by 4 wickets"; its old ball-level facts are held back, not mixed in |
| `duplicate_files` | `M0051.json` (identical re-send) | No change to any number; Data Quality shows the file as a duplicate |
| `malformed_files` | broken JSON, JSON without a match ID, CSV with the wrong columns | All three rejected with a reason on the Data Quality dashboard; the rest of the run completes |

Exact before / after values for each scenario: [README, Additional challenge](../README.md#-additional-challenge-add-new-data). Details: `02_SampleData/source/demo_changes/README.md`.

### D2. Your own match and CSV files

Copy files into `02_SampleData\_runtime\inbound\`, then run C2.

| Data | File name | Format |
|---|---|---|
| A match | `<anything>.json`, e.g. `M0122.json` | `02_SampleData/source/json/JSON_SCHEMA.md`; copy any file in `source/json/matches/` as a template and give it a new `match_id` |
| Ball by ball | must start with `deliveries`, e.g. `deliveries_M0122.csv` | `02_SampleData/source/csv/CSV_SCHEMA.md` |
| Player rankings | must start with `player_rankings` | same |
| Historical stats | must start with `historical_stats` | same |

Workflow 03 routes a CSV by its name prefix; a CSV with any other name is rejected as `schema_mismatch` by the
data-quality gate, never silently loaded. Codes for teams, venues and players must exist in `CricketSource`
(add them first, D3), otherwise the rows are rejected with a referential-integrity reason and listed on the Data
Quality dashboard. Re-sending an unchanged file is detected by its content hash and skipped.

### D3. New or changed master data (SQL Server source)

Workflow 01 reads `CricketSource` live on every run, so a change there needs no file:

```sql
INSERT INTO CricketSource.dbo.Venues (VenueCode, VenueName, City, Country, Capacity)
VALUES ('PUN02', 'Pune Stadium', 'Pune', 'India', 37000);
INSERT INTO CricketSource.dbo.Players (PlayerCode, FullName, DateOfBirth, Country, BattingStyle, BowlingStyle, PlayerRole, DebutDate)
VALUES ('P0153', 'Arjun Mehta', '1996-03-14', 'India', 'Right-hand bat', 'Right-arm medium', 'AllRounder', '2018-04-01');
```

Run C2: the new venue and player are loaded into the warehouse dimensions, and match and CSV files can now use
the codes `PUN02` and `P0153` (D2). A team's name history (Type-2, e.g. Delhi Falcons → Delhi Comets) comes from
the team name carried in each match file, not from this table.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `sqlcmd` not found | Install it (A2) and open a new terminal. |
| "The certificate chain was issued by an authority that is not trusted" | Run `sqlcmd` with `-C` (trust the local server certificate); the setup scripts already do. |
| `sqlcmd` cannot connect to `localhost\SQLEXPRESS` | Check the instance name (B2). In **SQL Server Configuration Manager**, enable **TCP/IP** for the instance and start the **SQL Server Browser** service, then restart SQL Server. |
| `create_odbc_dsns.bat` says administrator rights needed | Right-click → Run as administrator. |
| `relink_connections.py` finds 0 or 2 connections | Create exactly one connection per DSN (B6); delete stray copies in Manage Connections. |
| A tool says its connection is missing | Close Designer, run B7 again, reopen the workflow. |
| Designer offers to "Update Missing Macros" | Click **Close**, not Update (Update writes this PC's absolute paths into the workflow). Every macro is referenced relative to the workflow folder, so this only appears if the repository folder structure was changed; restore it from git. |
| Pre-flight: "run stuck in Started" | A previous run was interrupted. Read the error in the Results window, then: `sqlcmd -S <instance> -E -Q "EXEC CricketDW.audit.usp_AbandonStuckRuns @Reason = 'interrupted run'"`. If stage 04 failed, also run section 2 of `06_Tests\sql\reset_pipeline_state.sql`. |
| Stage 06 cannot write a `.hyper` file | Tableau has the workbook open. Close Tableau and run again. |
| "Not enough memory" | Close other applications; all stages share one engine process. |
| Start again from scratch | Run `06_Tests\sql\reset_pipeline_state.sql` (keeps the databases, clears pipeline state), then C1–C3. |
