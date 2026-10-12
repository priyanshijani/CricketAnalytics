-- Proves each least-privilege login can do its job and nothing else (01_Setup/sql/09_security.sql).
-- Run as an administrator: each test impersonates the login (EXECUTE AS LOGIN), attempts one action,
-- and records whether it was allowed. Every row should read PASS.
SET NOCOUNT ON;
USE master;
DECLARE @t TABLE (LoginName SYSNAME, Action NVARCHAR(200), ExpectAllowed BIT, Allowed BIT, Detail NVARCHAR(400));
DECLARE @login SYSNAME, @action NVARCHAR(200), @sql NVARCHAR(MAX), @expect BIT;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT LoginName, Action, Statement, ExpectAllowed FROM (VALUES
    -- source reader: CricketSource master data only
    (N'cricket_source_reader', N'Read CricketSource.dbo.Players',           N'IF EXISTS (SELECT TOP (1) * FROM CricketSource.dbo.Players) SET NOCOUNT ON', 1),
    (N'cricket_source_reader', N'Change CricketSource.dbo.Players',         N'UPDATE CricketSource.dbo.Players SET FullName = FullName WHERE 1 = 0', 0),
    (N'cricket_source_reader', N'Read CricketDW (any table)',               N'SELECT TOP (1) * FROM CricketDW.dw.Fact_MatchResult', 0),
    -- ETL writer: staging, warehouse, audit; rules read-only; no source, no DDL
    (N'cricket_etl_writer',    N'Read stg.MatchRaw',                        N'IF EXISTS (SELECT TOP (1) * FROM CricketDW.stg.MatchRaw) SET NOCOUNT ON', 1),
    (N'cricket_etl_writer',    N'Write stg (delete)',                       N'DELETE FROM CricketDW.stg.LoadReady_Control WHERE 1 = 0', 1),
    (N'cricket_etl_writer',    N'Write dw (update)',                        N'UPDATE CricketDW.dw.Fact_MatchResult SET Season = Season WHERE 1 = 0', 1),
    (N'cricket_etl_writer',    N'Write audit (insert)',                     N'INSERT INTO CricketDW.audit.Audit_PublishLog (LoadRunId, TableName, Operation, RowsAffected) SELECT ''x'', ''x'', ''x'', 0 WHERE 1 = 0', 1),
    (N'cricket_etl_writer',    N'Read config.DQRule',                       N'IF EXISTS (SELECT TOP (1) * FROM CricketDW.config.DQRule) SET NOCOUNT ON', 1),
    (N'cricket_etl_writer',    N'Change config.DQRule (rule SQL)',          N'UPDATE CricketDW.config.DQRule SET IsActive = IsActive WHERE 1 = 0', 0),
    (N'cricket_etl_writer',    N'Run the publish procedure (permission)',   N'IF HAS_PERMS_BY_NAME(''CricketDW.dw.usp_PublishWarehouse'', ''OBJECT'', ''EXECUTE'') = 0 THROW 50000, ''no EXECUTE'', 1', 1),
    (N'cricket_etl_writer',    N'Create a table (DDL)',                     N'EXEC(''USE CricketDW; CREATE TABLE stg.zz_security_probe (x INT); DROP TABLE stg.zz_security_probe;'')', 0),
    (N'cricket_etl_writer',    N'Read CricketSource',                       N'IF EXISTS (SELECT TOP (1) * FROM CricketSource.dbo.Players) SET NOCOUNT ON', 0),
    -- reporting reader: rpt views only
    (N'cricket_rpt_reader',    N'Read rpt.TeamSeason (view)',               N'IF EXISTS (SELECT TOP (1) * FROM CricketDW.rpt.TeamSeason) SET NOCOUNT ON', 1),
    (N'cricket_rpt_reader',    N'Read rpt.DQIssue (view over audit)',       N'IF EXISTS (SELECT TOP (1) * FROM CricketDW.rpt.DQIssue) SET NOCOUNT ON', 1),
    (N'cricket_rpt_reader',    N'Read dw.Fact_MatchResult (base table)',    N'SELECT TOP (1) * FROM CricketDW.dw.Fact_MatchResult', 0),
    (N'cricket_rpt_reader',    N'Read audit.Audit_DQException (base table)', N'SELECT TOP (1) * FROM CricketDW.audit.Audit_DQException', 0),
    (N'cricket_rpt_reader',    N'Read stg.MatchRaw (staging)',              N'IF EXISTS (SELECT TOP (1) * FROM CricketDW.stg.MatchRaw) SET NOCOUNT ON', 0),
    (N'cricket_rpt_reader',    N'Change anything (delete via view)',        N'DELETE FROM CricketDW.rpt.Player WHERE 1 = 0', 0),
    (N'cricket_rpt_reader',    N'Read CricketSource',                       N'IF EXISTS (SELECT TOP (1) * FROM CricketSource.dbo.Players) SET NOCOUNT ON', 0)
) AS v (LoginName, Action, Statement, ExpectAllowed);

OPEN c;
FETCH NEXT FROM c INTO @login, @action, @sql, @expect;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @allowed BIT = 1, @detail NVARCHAR(400) = N'';
    BEGIN TRY
        EXECUTE AS LOGIN = @login;
        EXEC (@sql);
        REVERT;
    END TRY
    BEGIN CATCH
        IF ORIGINAL_LOGIN() <> SUSER_SNAME() REVERT;
        SET @allowed = 0;
        SET @detail = LEFT(ERROR_MESSAGE(), 400);
    END CATCH;
    INSERT INTO @t VALUES (@login, @action, @expect, @allowed, @detail);
    FETCH NEXT FROM c INTO @login, @action, @sql, @expect;
END;
CLOSE c;

SELECT LoginName, Action,
       CASE ExpectAllowed WHEN 1 THEN 'allowed' ELSE 'denied' END AS Expected,
       CASE Allowed WHEN 1 THEN 'allowed' ELSE 'denied' END AS Actual,
       CASE WHEN ExpectAllowed = Allowed THEN 'PASS' ELSE 'FAIL' END AS Result,
       Detail
FROM @t;

-- Who else can connect: server logins that are not sysadmin-managed service accounts. BUILTIN\Users, if listed,
-- lets every local Windows user connect - review it (see 07_Docs/security.md).
SELECT name, type_desc, is_disabled FROM sys.server_principals
WHERE type IN ('S', 'U', 'G') AND name NOT LIKE '##%' AND name NOT LIKE 'NT %' ORDER BY name;

-- Every rpt view is readable by the reporting login (expect 0 rows - any row is a view it cannot read).
DECLARE @v SYSNAME;
DECLARE @failed TABLE (ViewName SYSNAME, Error NVARCHAR(400));
DECLARE vc CURSOR LOCAL FAST_FORWARD FOR
    SELECT v.name FROM CricketDW.sys.views AS v JOIN CricketDW.sys.schemas AS s ON s.schema_id = v.schema_id WHERE s.name = N'rpt' ORDER BY v.name;
OPEN vc;
FETCH NEXT FROM vc INTO @v;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXECUTE AS LOGIN = N'cricket_rpt_reader';
        EXEC (N'IF EXISTS (SELECT TOP (1) * FROM CricketDW.rpt.' + @v + N') SET NOCOUNT ON');
        REVERT;
    END TRY
    BEGIN CATCH
        IF ORIGINAL_LOGIN() <> SUSER_SNAME() REVERT;
        INSERT INTO @failed VALUES (@v, LEFT(ERROR_MESSAGE(), 400));
    END CATCH;
    FETCH NEXT FROM vc INTO @v;
END;
CLOSE vc;
SELECT ViewName AS UnreadableByReportingLogin, Error FROM @failed;
