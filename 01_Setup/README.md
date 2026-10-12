# 01_Setup

Step 1: prerequisites, databases and connections. Run in this order (full guide: `07_Docs/deployment.md`, part B):

1. `check_prerequisites.bat` — checks `config/local.config`, `sqlcmd` (go-sqlcmd) on PATH and ODBC Driver 17 for
   SQL Server; reports what is missing.
2. `setup_database.bat` — creates `CricketSource` and `CricketDW`, runs every script in `sql/` in order, seeds
   `CricketSource` from `02_SampleData/source/sql_server/seed_data.sql` and creates the `rpt` views.
3. `create_odbc_dsns.bat` (**Run as administrator**) — creates the System DSNs `CricketSource_DSN` and
   `CricketDW_DSN` that the Alteryx connections use, and verifies each saved its default database.

`sql/` holds the DDL itself — see `sql/README.md` for the script order.
