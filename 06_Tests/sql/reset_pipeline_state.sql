-- Resets the pipeline so workflows 04 -> 04b -> 05 run as a fresh baseline load.
--
-- Clears: the warehouse (dw.*, except Dim_Date), the publish log, the DQ state (file control, exceptions,
--         run measurements and scores) and the stg.*Valid queue.
-- Keeps:  config.DQRule / DQEntity (rules), config.Parameter, stg.*Raw and stg.*Snapshot (staged data from
--         workflows 01-03), dw.Dim_Date (calendar from setup) and audit.Audit_ETLRunLog (run history).
--
-- To reset only the DQ state and keep the warehouse, run section 2 alone: re-running 04 then 05 afterwards
-- republishes the same data in place, with the same keys.
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
TRUNCATE TABLE audit.Audit_PublishLog;
GO

-- 2. DQ state and the validated queue
TRUNCATE TABLE audit.Audit_FileControl;      -- incremental scope: empty = every staged file is new
TRUNCATE TABLE audit.Audit_DQException;
TRUNCATE TABLE audit.DQRunEntity;
TRUNCATE TABLE audit.DQRunScore;
TRUNCATE TABLE stg.MatchValid;
TRUNCATE TABLE stg.InningsValid;
TRUNCATE TABLE stg.BallByBallValid;
TRUNCATE TABLE stg.PlayerRankingValid;
TRUNCATE TABLE stg.HistoricalStatsValid;
TRUNCATE TABLE stg.PlayersValid;
TRUNCATE TABLE stg.MatchCompletenessValid;
GO

-- Optional: clear the run history of these workflows
-- DELETE FROM audit.Audit_ETLRunLog
-- WHERE WorkflowName IN ('04_dq_validation', '04b_dq_feedback', '05_transform_load');

-- Check.  expect PendingFiles 128 (if lower, re-run 02 and 03 - staging changed), every other column 0.
-- stg.LoadReady_* are emptied by every successful publish and overwritten by every 05 run, so they need no reset.
SELECT (SELECT COUNT(*) FROM stg.vw_DQPendingFile)    AS PendingFiles,
       (SELECT COUNT(*) FROM audit.Audit_FileControl) AS FileControl,
       (SELECT COUNT(*) FROM audit.Audit_DQException) AS Exceptions,
       (SELECT COUNT(*) FROM stg.MatchValid)          AS MatchValid,
       (SELECT COUNT(*) FROM dw.Fact_MatchResult)     AS WarehouseMatches,
       (SELECT COUNT(*) FROM dw.Dim_Team)             AS DimTeam;
