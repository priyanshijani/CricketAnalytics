-- CricketDW: support for the pipeline orchestrator (03_Alteryx/workflows/00_orchestrator.yxmd).
--
-- audit.vw_StuckRun            workflows whose most recent run-log row is still 'Started': the run crashed,
--                              was cancelled, or is running right now. The orchestrator's pre-flight refuses
--                              to start while any exist - a guard against a concurrent or half-finished run.
-- audit.usp_AbandonStuckRuns   an administrator's deliberate decision to mark those runs 'Abandoned' after
--                              investigating them, so the pipeline can start again.
-- audit.vw_PipelineRun         one row per orchestrated run (run timestamp) per workflow, for the run summary.
-- Idempotent: safe to re-run.

USE CricketDW;
GO

CREATE OR ALTER VIEW audit.vw_StuckRun AS
SELECT l.WorkflowName, l.LoadRunId, l.StartTime, DATEDIFF(MINUTE, l.StartTime, SYSDATETIME()) AS MinutesSinceStart
FROM (SELECT r.*, ROW_NUMBER() OVER (PARTITION BY r.WorkflowName ORDER BY r.RunLogId DESC) AS rn
      FROM audit.Audit_ETLRunLog AS r) AS l
WHERE l.rn = 1 AND l.Status = 'Started';
GO

CREATE OR ALTER PROCEDURE audit.usp_AbandonStuckRuns
    @Reason VARCHAR(900)
AS
BEGIN
    SET NOCOUNT ON;
    IF NULLIF(LTRIM(@Reason), '') IS NULL
        THROW 50020, 'Give a reason: abandoning a run is a recorded decision.', 1;
    INSERT INTO audit.Audit_ETLRunLog (LoadRunId, WorkflowName, StartTime, EndTime, Status, RowsIn, RowsOut, RowsRejected, ErrorMessage)
    SELECT s.LoadRunId, s.WorkflowName, s.StartTime, SYSDATETIME(), 'Abandoned', NULL, NULL, NULL, LEFT(CONCAT('Abandoned: ', @Reason), 1000)
    FROM audit.vw_StuckRun AS s;
    SELECT @@ROWCOUNT AS RunsAbandoned;
END
GO

-- Every workflow's LoadRunId is "<workflow>_<yyyymmddHHMMSS>", the timestamp being the start of the top-level
-- run (DateTimeStart). Runs started by the orchestrator therefore share one RunStamp across all stages.
CREATE OR ALTER VIEW audit.vw_PipelineRun AS
SELECT RIGHT(LoadRunId, 14) AS RunStamp, WorkflowName,
       MIN(StartTime) AS StartTime, MAX(EndTime) AS EndTime,
       CASE WHEN SUM(CASE WHEN Status = 'Succeeded' THEN 1 ELSE 0 END) > 0 THEN 'Succeeded'
            WHEN SUM(CASE WHEN Status = 'Abandoned' THEN 1 ELSE 0 END) > 0 THEN 'Abandoned'
            WHEN SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END) > 0 THEN 'Failed'
            ELSE 'Started' END AS Status,
       MAX(RowsIn) AS RowsIn, MAX(RowsOut) AS RowsOut, MAX(RowsRejected) AS RowsRejected
FROM audit.Audit_ETLRunLog
WHERE LoadRunId LIKE '%[_][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
GROUP BY RIGHT(LoadRunId, 14), WorkflowName;
GO
