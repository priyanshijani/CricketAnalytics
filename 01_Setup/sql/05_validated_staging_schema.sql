-- CricketDW: validated staging tables written by Alteryx workflow 04_dq_validation.
-- File-based tables (Match, Innings, BallByBall, PlayerRanking, HistoricalStats) are a queue: 04 appends
-- the rows of new or changed files that passed every Rejected-severity rule, typed; workflow 05 loads them
-- and then deletes what it loaded. When a corrected file arrives before 05 has run, the queue holds both
-- versions - 05 takes the latest LoadRunId per match. stg.PlayersValid is replaced every run (full master).
-- Workflow 05 reads only these tables, never stg.*Raw. Failed rows are in audit.Audit_DQException.
-- Idempotent: safe to re-run against an existing database.

USE CricketDW;
GO

IF OBJECT_ID(N'stg.MatchValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.MatchValid (
        MatchId             VARCHAR(50)  NOT NULL,
        MatchDate           DATE         NOT NULL,
        FormatCode          VARCHAR(10)  NOT NULL,
        Team1Code           VARCHAR(10)  NOT NULL,
        Team2Code           VARCHAR(10)  NOT NULL,
        VenueCode           VARCHAR(20)  NOT NULL,
        TossWinnerCode      VARCHAR(10)  NULL,
        TossDecision        VARCHAR(20)  NULL,
        WinnerCode          VARCHAR(10)  NULL,      -- NULL for Tied / NoResult / Abandoned
        ResultMethod        VARCHAR(20)  NOT NULL,
        WinMargin           INT          NULL,
        WinMarginType       VARCHAR(20)  NULL,
        ManOfMatchCode      VARCHAR(20)  NULL,
        Season              VARCHAR(20)  NULL,
        FileStatus          VARCHAR(15)  NOT NULL,  -- New / Reprocessed (corrected file: 05 replaces the match)
        SourceFileName      VARCHAR(260) NOT NULL,
        SourceFileHash      CHAR(64)     NOT NULL,
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.InningsValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.InningsValid (
        MatchId             VARCHAR(50)  NOT NULL,
        InningsNo           TINYINT      NOT NULL,  -- 1-based (stg.InningsRaw is 0-based array position)
        BattingTeamCode     VARCHAR(10)  NOT NULL,
        BowlingTeamCode     VARCHAR(10)  NOT NULL,
        RunsScored          INT          NOT NULL,
        WicketsLost         INT          NOT NULL,
        OversPlayed         DECIMAL(4,1) NOT NULL,
        ExtrasTotal         INT          NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.BallByBallValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.BallByBallValid (
        MatchId             VARCHAR(50)  NOT NULL,
        InningsNo           TINYINT      NOT NULL,
        OverNo              INT          NOT NULL,
        BallNo              INT          NOT NULL,
        BatsmanCode         VARCHAR(20)  NOT NULL,
        BowlerCode          VARCHAR(20)  NOT NULL,
        RunsOffBat          INT          NOT NULL,
        ExtraRuns           INT          NOT NULL,
        ExtraType           VARCHAR(20)  NULL,
        IsWicket            BIT          NOT NULL,
        DismissalType       VARCHAR(30)  NULL,
        DismissedPlayerCode VARCHAR(20)  NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.PlayerRankingValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.PlayerRankingValid (
        PlayerCode          VARCHAR(20)  NOT NULL,
        FormatCode          VARCHAR(10)  NOT NULL,
        Discipline          VARCHAR(20)  NOT NULL,
        RankingDate         DATE         NOT NULL,  -- parsed from dd/mm/yyyy
        RankPosition        INT          NOT NULL,
        RatingPoints        INT          NOT NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.HistoricalStatsValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.HistoricalStatsValid (
        PlayerCode          VARCHAR(20)  NOT NULL,
        Season              VARCHAR(20)  NOT NULL,
        FormatCode          VARCHAR(10)  NOT NULL,
        MatchesPlayed       INT          NOT NULL,
        RunsScored          INT          NOT NULL,
        WicketsTaken        INT          NOT NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.PlayersValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.PlayersValid (
        PlayerCode          VARCHAR(20)  NOT NULL,
        FullName            VARCHAR(150) NOT NULL,
        DateOfBirth         DATE         NULL,      -- future dates are defaulted to NULL (rule future_date_of_birth)
        Country             VARCHAR(50)  NULL,
        BattingStyle        VARCHAR(30)  NULL,
        BowlingStyle        VARCHAR(30)  NULL,
        PlayerRole          VARCHAR(30)  NULL,
        DebutDate           DATE         NULL,
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO

-- Match-level completeness, one row per match touched by a 04 run (queue, consumed by 05).
-- The match is the unit of acceptance for ball-by-ball: if any delivery of a match fails, or the
-- match's scorecard disagrees with its deliveries, every delivery of that match is held back.
-- A NULL status means "not evaluated in this run" - 05 keeps the match's previous status.
IF OBJECT_ID(N'stg.MatchCompletenessValid', N'U') IS NULL
BEGIN
    CREATE TABLE stg.MatchCompletenessValid (
        MatchId             VARCHAR(50)  NOT NULL,
        InningsStatus       VARCHAR(15)  NULL,      -- Complete / Incomplete (an innings was rejected)
        BallByBallStatus    VARCHAR(15)  NULL,      -- Loaded / Held (05 removes held ball-by-ball facts)
        LoadRunId           VARCHAR(50)  NOT NULL
    );
END
GO
