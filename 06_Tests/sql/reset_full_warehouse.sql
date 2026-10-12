-- Full reset of CricketDW: removes every row any workflow has written, including all run history,
-- so the next run of 00_orchestrator.yxmd builds the database from nothing.
--
-- Clears: staging (stg.*Raw, *Snapshot, *Valid, LoadReady_*), the warehouse (dw.*, except Dim_Date),
--         all audit tables (run log, file control, DQ exceptions, run scores, publish log).
-- Keeps:  config.DQRule / DQEntity / Parameter (rules and settings from setup), dw.Dim_Date (calendar
--         from setup), the rpt views and functions, the logins, and the CricketSource database.
--
-- Afterwards: run 02_SampleData/stage_source_files.bat (only needed if the inbound folder is not the
-- baseline), then run 00_orchestrator.yxmd. Expected results: 06_Tests/results/2026-10-06_export_orchestration.md.
USE CricketDW;
GO
SET NOCOUNT ON;

-- 1. Warehouse - children before parents (foreign keys), then restart the surrogate keys at 1
DELETE FROM dw.Fact_Partnership;
DELETE FROM dw.Fact_FallOfWicket;
DELETE FROM dw.Agg_OverSummary;
DELETE FROM dw.Fact_BattingPerformance;
DELETE FROM dw.Fact_BowlingPerformance;
DELETE FROM dw.Fact_BallByBall;
DELETE FROM dw.Fact_Innings;
DELETE FROM dw.Bridge_PlayerTeamSeason;
DELETE FROM dw.Fact_PlayerRanking;
DELETE FROM dw.Fact_PlayerSeasonStats;
DELETE FROM dw.Fact_MatchResult;
DELETE FROM dw.Dim_Team;
DELETE FROM dw.Dim_Player;
DELETE FROM dw.Dim_Venue;
DELETE FROM dw.Dim_MatchFormat;
DBCC CHECKIDENT ('dw.Fact_MatchResult', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.Dim_Team', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.Dim_Player', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.Dim_Venue', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.Dim_MatchFormat', RESEED, 0) WITH NO_INFOMSGS;
GO

-- 2. Audit - all run history, file control, DQ results and the publish log
TRUNCATE TABLE audit.Audit_ETLRunLog;
TRUNCATE TABLE audit.Audit_FileControl;
TRUNCATE TABLE audit.Audit_DQException;
TRUNCATE TABLE audit.DQRunEntity;
TRUNCATE TABLE audit.DQRunScore;
TRUNCATE TABLE audit.Audit_PublishLog;
GO

-- 3. Staging - every stg table (bronze *Raw / *Snapshot, silver *Valid, transient LoadReady_*)
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'TRUNCATE TABLE stg.' + QUOTENAME(t.name) + N';' + CHAR(10)
FROM sys.tables AS t
WHERE t.schema_id = SCHEMA_ID('stg');
EXEC sys.sp_executesql @sql;
GO

-- Check: every row 0 except the kept tables (Dim_Date 1826, DQRule 43, DQEntity 7, Parameter 5)
SELECT s.name + '.' + t.name AS TableName, SUM(p.rows) AS RowsLeft
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name
HAVING SUM(p.rows) > 0
ORDER BY TableName;
