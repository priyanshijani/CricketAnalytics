-- CricketSource: master/reference data, standing in for a pre-existing system.
-- Populated once by 02_SampleData/source/sql_server/seed_data.sql, then queried live by
-- Alteryx workflow 01_ingest_sql on every pipeline run.
-- Idempotent: safe to re-run against an existing database.

USE CricketSource;
GO

IF OBJECT_ID(N'dbo.Teams', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Teams (
        TeamId          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        TeamCode        VARCHAR(10)  NOT NULL,      -- stable natural key, survives renames
        TeamName        VARCHAR(100) NOT NULL,      -- current display name
        Country         VARCHAR(50)  NULL,
        FoundedYear     INT          NULL,
        IsActive        BIT          NOT NULL CONSTRAINT DF_Teams_IsActive DEFAULT (1)
    );
END
GO

IF OBJECT_ID(N'dbo.Players', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Players (
        PlayerId        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PlayerCode      VARCHAR(20)  NOT NULL,      -- natural key
        FullName        VARCHAR(150) NOT NULL,
        DateOfBirth     DATE         NULL,          -- nullable: planted missing-data scenario
        Country         VARCHAR(50)  NULL,
        BattingStyle    VARCHAR(30)  NULL,
        BowlingStyle    VARCHAR(30)  NULL,
        PlayerRole      VARCHAR(30)  NULL,          -- Batter / Bowler / AllRounder / WicketKeeper
        DebutDate       DATE         NULL
    );
END
GO

IF OBJECT_ID(N'dbo.Venues', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Venues (
        VenueId         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        VenueCode       VARCHAR(20)  NOT NULL,
        VenueName       VARCHAR(150) NOT NULL,
        City            VARCHAR(100) NULL,          -- nullable: planted missing-data scenario
        Country         VARCHAR(50)  NULL,
        Capacity        INT          NULL
    );
END
GO
