-- CricketDW: audit/control tables and pipeline configuration.
-- audit  - file-control tracking, data-quality exceptions, ETL run logging.
-- config - runtime parameters (folder names, thresholds), read by Alteryx so no path or
--          environment-specific value is hardcoded in workflow XML.
-- Idempotent: safe to re-run against an existing database.

USE CricketDW;
GO

IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit');
GO
IF SCHEMA_ID(N'config') IS NULL EXEC(N'CREATE SCHEMA config');
GO

IF OBJECT_ID(N'audit.Audit_FileControl', N'U') IS NULL
BEGIN
    CREATE TABLE audit.Audit_FileControl (
        FileControlId   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        FileName        VARCHAR(260) NOT NULL,
        FileHash        CHAR(64)     NOT NULL,
        SourceType      VARCHAR(10)  NOT NULL,   -- JSON / CSV
        LoadRunId       VARCHAR(50) NOT NULL,
        LoadTimestamp   DATETIME2    NOT NULL CONSTRAINT DF_FileControl_Timestamp DEFAULT (SYSUTCDATETIME()),
        Status          VARCHAR(15)  NOT NULL,   -- New / Reprocessed / Duplicate / Rejected
        RowsRead        INT          NULL,
        RowsLoaded      INT          NULL,
        RowsRejected    INT          NULL
    );
    CREATE INDEX IX_FileControl_Hash ON audit.Audit_FileControl (FileHash);
END
GO

IF OBJECT_ID(N'audit.Audit_DQException', N'U') IS NULL
BEGIN
    CREATE TABLE audit.Audit_DQException (
        ExceptionId     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        LoadRunId       VARCHAR(50) NOT NULL,
        SourceFile      VARCHAR(260) NULL,
        EntityType      VARCHAR(30)  NOT NULL,   -- Match / Player / Team / Venue / Delivery / ...
        NaturalKey      VARCHAR(100) NULL,
        RuleViolated    VARCHAR(100) NOT NULL,
        RawValue        VARCHAR(200) NULL,
        ActionTaken     VARCHAR(20)  NOT NULL,   -- Rejected / Flagged / Defaulted
        LoadTimestamp   DATETIME2    NOT NULL CONSTRAINT DF_DQException_Timestamp DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_DQException_RunId ON audit.Audit_DQException (LoadRunId);
END
GO

IF OBJECT_ID(N'audit.Audit_ETLRunLog', N'U') IS NULL
BEGIN
    CREATE TABLE audit.Audit_ETLRunLog (
        RunLogId        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        LoadRunId        VARCHAR(50) NOT NULL,
        WorkflowName       VARCHAR(60) NOT NULL,
        StartTime            DATETIME2 NOT NULL,
        EndTime                DATETIME2 NULL,
        Status                   VARCHAR(15) NOT NULL,  -- Started / Succeeded / Failed
        RowsIn                     INT NULL,
        RowsOut                      INT NULL,
        RowsRejected                   INT NULL,
        ErrorMessage                     VARCHAR(1000) NULL
    );
    CREATE INDEX IX_ETLRunLog_RunId ON audit.Audit_ETLRunLog (LoadRunId);
END
GO

IF OBJECT_ID(N'config.Parameter', N'U') IS NULL
BEGIN
    CREATE TABLE config.Parameter (
        ParameterName   VARCHAR(100) NOT NULL PRIMARY KEY,
        ParameterValue  VARCHAR(260) NOT NULL,
        Description     VARCHAR(300) NULL
    );

    INSERT INTO config.Parameter (ParameterName, ParameterValue, Description) VALUES
        (N'InboundFolderName',  N'inbound', N'Runtime folder Alteryx watches for files to ingest, relative to 02_SampleData/_runtime/'),
        (N'ArchiveFolderName',  N'archive', N'Runtime folder successfully processed files are moved to'),
        (N'ErrorFolderName',    N'error',   N'Runtime folder malformed/rejected files are moved to'),
        (N'PreparedFolderName', N'04_Prepared', N'Folder Alteryx export writes rpt_* CSVs to, relative to the repo root'),
        (N'MaxWicketsPerInnings', N'10', N'Business-rule threshold used by DQ validation');
END
GO
