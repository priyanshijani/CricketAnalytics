-- Least-privilege access: three SQL logins, each scoped to one database and one job.
--
--   cricket_source_reader  CricketSource : SELECT on dbo (the master data)            - used by workflow 01
--   cricket_etl_writer     CricketDW     : read/write stg, dw, audit; read config;
--                                          EXECUTE dw.usp_PublishWarehouse             - used by workflows 01-05
--   cricket_rpt_reader     CricketDW     : SELECT + EXECUTE on the rpt schema only     - used by workflow 06 / reporting
--
-- Permissions are granted to database roles (source_reader, etl_writer, report_reader), never to the login
-- directly, so a person or service account is given access by role membership alone.
-- The reporting login can read rpt views without any permission on dw / audit: every schema is owned by dbo,
-- so SQL Server's ownership chaining lets a view read its base tables on the caller's behalf. It cannot query
-- a base table directly, or see a column a view does not expose.
-- The ETL writer can READ config (the DQ rules) but not change it: rule SQL is executed by the pipeline, so
-- write access to config.DQRule is deliberately kept off the ETL identity.
--
-- Passwords are sqlcmd variables supplied by setup_database.bat from config/local.config (gitignored):
--   SOURCE_READER_PASSWORD, ETL_WRITER_PASSWORD, RPT_READER_PASSWORD
-- Idempotent: re-running re-syncs passwords and grants.

USE master;
GO
IF SUSER_ID(N'cricket_source_reader') IS NULL
    CREATE LOGIN cricket_source_reader WITH PASSWORD = N'$(SOURCE_READER_PASSWORD)', DEFAULT_DATABASE = CricketSource, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
ELSE
    ALTER LOGIN cricket_source_reader WITH PASSWORD = N'$(SOURCE_READER_PASSWORD)';
IF SUSER_ID(N'cricket_etl_writer') IS NULL
    CREATE LOGIN cricket_etl_writer WITH PASSWORD = N'$(ETL_WRITER_PASSWORD)', DEFAULT_DATABASE = CricketDW, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
ELSE
    ALTER LOGIN cricket_etl_writer WITH PASSWORD = N'$(ETL_WRITER_PASSWORD)';
IF SUSER_ID(N'cricket_rpt_reader') IS NULL
    CREATE LOGIN cricket_rpt_reader WITH PASSWORD = N'$(RPT_READER_PASSWORD)', DEFAULT_DATABASE = CricketDW, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
ELSE
    ALTER LOGIN cricket_rpt_reader WITH PASSWORD = N'$(RPT_READER_PASSWORD)';
GO

-- ---------------- CricketSource ----------------
USE CricketSource;
GO
IF DATABASE_PRINCIPAL_ID(N'source_reader') IS NULL CREATE ROLE source_reader AUTHORIZATION dbo;
GRANT SELECT ON SCHEMA::dbo TO source_reader;
IF DATABASE_PRINCIPAL_ID(N'cricket_source_reader') IS NULL CREATE USER cricket_source_reader FOR LOGIN cricket_source_reader;
ALTER ROLE source_reader ADD MEMBER cricket_source_reader;
GO

-- ---------------- CricketDW ----------------
USE CricketDW;
GO
IF SCHEMA_ID(N'rpt') IS NULL EXEC(N'CREATE SCHEMA rpt AUTHORIZATION dbo');
GO
IF DATABASE_PRINCIPAL_ID(N'etl_writer') IS NULL CREATE ROLE etl_writer AUTHORIZATION dbo;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::stg   TO etl_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dw    TO etl_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::audit TO etl_writer;
GRANT SELECT ON SCHEMA::config TO etl_writer;
GRANT EXECUTE ON OBJECT::dw.usp_PublishWarehouse TO etl_writer;
IF DATABASE_PRINCIPAL_ID(N'cricket_etl_writer') IS NULL CREATE USER cricket_etl_writer FOR LOGIN cricket_etl_writer;
ALTER ROLE etl_writer ADD MEMBER cricket_etl_writer;

IF DATABASE_PRINCIPAL_ID(N'report_reader') IS NULL CREATE ROLE report_reader AUTHORIZATION dbo;
GRANT SELECT ON SCHEMA::rpt TO report_reader;
-- The business-rule functions (rpt.fn_*) are part of the published contract. Granted explicitly because
-- SQL Server 2019 scalar-UDF inlining checks EXECUTE even inside a view, despite ownership chaining.
GRANT EXECUTE ON SCHEMA::rpt TO report_reader;
IF DATABASE_PRINCIPAL_ID(N'cricket_rpt_reader') IS NULL CREATE USER cricket_rpt_reader FOR LOGIN cricket_rpt_reader;
ALTER ROLE report_reader ADD MEMBER cricket_rpt_reader;
GO
