-- CricketDW: data-quality measurement and feedback loop (TDQM: define -> measure -> analyse -> improve).
--
-- Measure  - audit.DQRunEntity      rows in / valid / rejected per entity per 04 run (written by 04).
--            Audit_DQException gains RuleId + StgRowId, so every exception names the exact rule and row.
-- Analyse  - audit.DQRunScore       quality score per run, entity and DQ dimension (written by 04b).
--            audit.vw_DQIssue       one row per distinct issue with its lifecycle: Open / Resolved,
--                                   first seen, runs seen, age, owner, root cause, remediation.
--            audit.vw_DQRootCause   open issues rolled up by root cause, owner and rule (Pareto input).
--            audit.vw_DQScoreTrend  score history, for the Tableau DQ view.
-- Improve  - workflow 04b writes one open-issues report per owner to 02_SampleData/_runtime/dq_reports.
-- Idempotent: safe to re-run.

USE CricketDW;
GO

IF COL_LENGTH(N'audit.Audit_DQException', N'RuleId') IS NULL
    ALTER TABLE audit.Audit_DQException ADD RuleId INT NULL, StgRowId BIGINT NULL;
GO

IF OBJECT_ID(N'audit.DQRunEntity', N'U') IS NULL
BEGIN
    CREATE TABLE audit.DQRunEntity (
        LoadRunId       VARCHAR(50)  NOT NULL,
        EntityType      VARCHAR(30)  NOT NULL,
        RowsIn          INT          NOT NULL,
        RowsValid       INT          NOT NULL,
        RowsRejected    INT          NOT NULL,
        RecordedAtUtc   DATETIME2    NOT NULL CONSTRAINT DF_DQRunEntity_At DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_DQRunEntity PRIMARY KEY (LoadRunId, EntityType)
    );
END
GO

IF OBJECT_ID(N'audit.DQRunScore', N'U') IS NULL
BEGIN
    CREATE TABLE audit.DQRunScore (
        LoadRunId       VARCHAR(50)  NOT NULL,
        EntityType      VARCHAR(30)  NOT NULL,
        Dimension       VARCHAR(20)  NOT NULL,   -- a DQ dimension, or 'Overall' (row accepted into stg.*Valid)
        RowsChecked     INT          NOT NULL,
        RowsFailed      INT          NOT NULL,   -- distinct rows with at least one violation in this dimension
        ScorePct        DECIMAL(5,2) NOT NULL,   -- 100 * (RowsChecked - RowsFailed) / RowsChecked
        ScoredAtUtc     DATETIME2    NOT NULL CONSTRAINT DF_DQRunScore_At DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_DQRunScore PRIMARY KEY (LoadRunId, EntityType, Dimension)
    );
END
GO

-- One row per distinct issue (entity + key + rule + source). Lifecycle is derived, never maintained by hand:
-- an issue is Open while the most recent run that validated its source still raised it, and Resolved once
-- a later run validated that source without raising it (a corrected file was accepted, or master data fixed).
-- Runs that skipped a file (identical content already processed) do not count as validating it.
CREATE OR ALTER VIEW audit.vw_DQIssue AS
WITH validating AS (
    SELECT FileName AS SourceFile, LoadRunId
    FROM audit.Audit_FileControl
    WHERE NOT (Status = 'Duplicate' AND RowsRead IS NULL)
    UNION
    SELECT 'CricketSource.dbo.Players', LoadRunId
    FROM audit.DQRunEntity
    WHERE EntityType = 'Player'
),
latest AS (
    SELECT SourceFile, MAX(LoadRunId) AS LatestValidatingRunId
    FROM validating
    GROUP BY SourceFile
),
issue AS (
    SELECT EntityType, NaturalKey, RuleViolated, SourceFile,
           MIN(LoadTimestamp) AS FirstSeenUtc,
           MAX(LoadTimestamp) AS LastSeenUtc,
           MAX(LoadRunId) AS LastSeenRunId,
           COUNT(DISTINCT LoadRunId) AS RunsSeen,
           MAX(ExceptionId) AS LastExceptionId
    FROM audit.Audit_DQException
    GROUP BY EntityType, NaturalKey, RuleViolated, SourceFile
)
SELECT
    i.EntityType, i.NaturalKey, i.RuleViolated, i.SourceFile,
    x.RawValue, x.ActionTaken,
    CASE WHEN i.LastSeenRunId >= l.LatestValidatingRunId OR l.LatestValidatingRunId IS NULL
         THEN 'Open' ELSE 'Resolved' END AS IssueStatus,
    i.FirstSeenUtc, i.LastSeenUtc, i.RunsSeen,
    DATEDIFF(DAY, i.FirstSeenUtc, SYSUTCDATETIME()) AS AgeDays,
    r.Dimension, r.RootCauseCategory, r.RemediationHint, r.PlantedIssue,
    e.OwnerCode, e.OwnerName
FROM issue AS i
JOIN audit.Audit_DQException AS x ON x.ExceptionId = i.LastExceptionId
LEFT JOIN latest AS l ON l.SourceFile = i.SourceFile
LEFT JOIN config.DQRule AS r ON r.EntityType = i.EntityType AND r.RuleCode = i.RuleViolated
LEFT JOIN config.DQEntity AS e ON e.EntityType = i.EntityType;
GO

-- Open issues by root cause / owner / rule - sort by OpenIssues DESC for a Pareto view.
CREATE OR ALTER VIEW audit.vw_DQRootCause AS
SELECT RootCauseCategory, OwnerCode, OwnerName, EntityType, RuleViolated, ActionTaken,
       COUNT(*) AS OpenIssues,
       COUNT(DISTINCT SourceFile) AS SourcesAffected,
       MAX(AgeDays) AS OldestAgeDays
FROM audit.vw_DQIssue
WHERE IssueStatus = 'Open'
GROUP BY RootCauseCategory, OwnerCode, OwnerName, EntityType, RuleViolated, ActionTaken;
GO

CREATE OR ALTER VIEW audit.vw_DQScoreTrend AS
SELECT s.LoadRunId, s.ScoredAtUtc, s.EntityType, s.Dimension, s.RowsChecked, s.RowsFailed, s.ScorePct
FROM audit.DQRunScore AS s;
GO
