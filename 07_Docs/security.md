# Security

Authentication, authorization and least privilege for the prototype, and what production would add.
Implemented in `01_Setup/sql/09_security.sql`; proven by `06_Tests/sql/check_security.sql`.

## Logins and roles

Three SQL logins, each scoped to one database and one job. Permissions are granted to database roles, never
to a login, so access is given or removed by role membership alone.

| Login | Role | Database | Can | Cannot | Used by |
|---|---|---|---|---|---|
| `cricket_source_reader` | `source_reader` | CricketSource | `SELECT` on `dbo` (Teams, Players, Venues) | Change master data; see `CricketDW` | Workflow `01` |
| `cricket_etl_writer` | `etl_writer` | CricketDW | Read and write `stg`, `dw`, `audit`; read `config`; execute `dw.usp_PublishWarehouse` | Change the DQ rules in `config`; create or alter objects (no DDL); see `CricketSource` | Workflows `01`–`05` |
| `cricket_rpt_reader` | `report_reader` | CricketDW | `SELECT` and `EXECUTE` on the `rpt` schema only | Read any base table (`dw`, `audit`, `stg`); change anything; see `CricketSource` | Workflow `06`, ad hoc reporting |

**How the reporting login reads data it has no table permission on:** every schema is owned by `dbo`, so
SQL Server's ownership chaining lets an `rpt` view read `dw` and `audit` tables on the caller's behalf. The
login sees exactly the columns a view exposes and nothing else. `EXECUTE` on `rpt` is granted as well because
the business-rule functions (`rpt.fn_*`) are part of the published contract, and SQL Server 2019's scalar-UDF
inlining checks that permission even inside a view.

**Why the ETL writer cannot change `config`:** the DQ rules in `config.DQRule` are T-SQL that the pipeline
executes. Keeping write access to them off the identity that runs the pipeline means a compromised or misused
ETL connection cannot inject SQL through a rule. Rules change through `06_dq_metadata_schema.sql`, run by an
administrator.

**Why the publish procedure deletes rather than truncates its load tables:** `TRUNCATE` needs `ALTER`
permission, which the ETL writer deliberately does not have.

## Credentials

- Passwords are never in tracked files. `config/local.config` (gitignored) holds `SOURCE_READER_PASSWORD`,
  `ETL_WRITER_PASSWORD` and `RPT_READER_PASSWORD`; `01_Setup/setup_database.bat` passes them to
  `09_security.sql` as sqlcmd variables. `config/local.config.example` has the empty keys.
- The logins use the Windows password policy (`CHECK_POLICY = ON`).
- Tableau needs no database credentials at all: it reads the prepared CSV files in `04_Prepared/`.

## Current state of the pipeline connections

The logins are created and their permissions proven, but the Alteryx connections still use Windows
authentication with the developer's account, which is a server administrator on this machine. Switching is a
deployment step, done in Designer:

1. Alteryx Connections → edit `CricketSource_DB` to SQL authentication with `cricket_source_reader`.
2. Edit `CricketDW_DB` to `cricket_etl_writer`.
3. Create a connection for workflow `06` with `cricket_rpt_reader`.
4. Re-run `01`–`06` and the test scripts. Confirm that Alteryx's "Delete Data & Append" output option issues
   `DELETE`, not `TRUNCATE`, under the writer login (`TRUNCATE` would need `ALTER`).

## Verify

Run `06_Tests/sql/check_security.sql` as an administrator. It impersonates each login (`EXECUTE AS LOGIN`),
attempts each allowed and forbidden action, and expects every row to read PASS. Then it confirms the reporting
login can read every `rpt` view, and lists every server login.

## Findings on this machine

- `BUILTIN\Users` has a server login, so every local Windows user can connect to the instance. It grants no
  database access by itself, but it widens who can reach the server. Remove it unless something depends on it.
- The developer's Windows account is `sysadmin`. That is normal for a development box; the pipeline should
  not run under it once the connections are switched.

## Production alternatives

| Prototype | Production |
|---|---|
| SQL logins with passwords in a local file | Windows / Entra ID service accounts, or a secrets vault (Alteryx Server credential store, Azure Key Vault) |
| Roles granted to individual logins | Roles granted to AD groups; access managed by group membership |
| Tableau reads CSV files | Tableau Server with its own read-only login on `rpt` and row-level security (a user-to-team filter table) |
| One instance for source and warehouse | Separate servers or instances, network rules between them |
| No auditing of logins | SQL Server Audit on logins and permission changes |
