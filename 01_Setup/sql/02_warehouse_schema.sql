-- CricketDW: staging landing tables and the conformed star schema.
-- stg  - raw landed rows from JSON/CSV ingestion (workflows 02, 03), read by DQ validation (04).
-- dw   - dimensions, bridge, and fact tables, loaded by transform/load (05).
-- Idempotent: safe to re-run against an existing database.

USE CricketDW;
GO

IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');
GO
IF SCHEMA_ID(N'dw') IS NULL EXEC(N'CREATE SCHEMA dw');
GO

-- ===========================================================================
-- Staging: one landing table per file-based source, plus a snapshot of the
-- live CricketSource read on each run (lets DQ validation check referential
-- integrity without a cross-database query on every rule).
-- ===========================================================================

IF OBJECT_ID(N'stg.TeamsSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE stg.TeamsSnapshot (
        TeamCode        VARCHAR(10)  NOT NULL,
        TeamName        VARCHAR(100) NOT NULL,
        Country         VARCHAR(50)  NULL,
        FoundedYear     INT          NULL,
        IsActive        BIT          NOT NULL,
        LoadRunId       VARCHAR(50) NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.PlayersSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE stg.PlayersSnapshot (
        PlayerCode      VARCHAR(20)  NOT NULL,
        FullName        VARCHAR(150) NOT NULL,
        DateOfBirth     DATE         NULL,
        Country         VARCHAR(50)  NULL,
        BattingStyle    VARCHAR(30)  NULL,
        BowlingStyle    VARCHAR(30)  NULL,
        PlayerRole      VARCHAR(30)  NULL,
        DebutDate       DATE         NULL,
        LoadRunId       VARCHAR(50) NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.VenuesSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE stg.VenuesSnapshot (
        VenueCode       VARCHAR(20)  NOT NULL,
        VenueName       VARCHAR(150) NOT NULL,
        City            VARCHAR(100) NULL,
        Country         VARCHAR(50)  NULL,
        Capacity        INT          NULL,
        LoadRunId       VARCHAR(50) NOT NULL
    );
END
GO

IF OBJECT_ID(N'stg.MatchRaw', N'U') IS NULL
BEGIN
    -- One row per source JSON file, flattened to header level. Nested innings/scores
    -- detail is parsed by Alteryx into stg.InningsRaw / stg.BattingRaw / stg.BowlingRaw.
    CREATE TABLE stg.MatchRaw (
        SourceFileName      VARCHAR(260) NOT NULL,
        SourceFileHash      CHAR(64)     NOT NULL,
        MatchIdRaw          VARCHAR(50)  NULL,      -- NULL is itself a planted malformed-file case
        MatchDateRaw        VARCHAR(30)  NULL,
        FormatCodeRaw       VARCHAR(10)  NULL,
        Team1CodeRaw        VARCHAR(10)  NULL,
        Team2CodeRaw        VARCHAR(10)  NULL,
        VenueCodeRaw        VARCHAR(20)  NULL,
        TossWinnerCodeRaw   VARCHAR(10)  NULL,
        TossDecisionRaw     VARCHAR(20)  NULL,
        WinnerCodeRaw       VARCHAR(10)  NULL,
        ResultMethodRaw     VARCHAR(20)  NULL,
        WinMarginRaw        VARCHAR(20)  NULL,
        WinMarginTypeRaw    VARCHAR(20)  NULL,
        ManOfMatchCodeRaw   VARCHAR(20)  NULL,
        SeasonRaw           VARCHAR(20)  NULL,
        LoadRunId           VARCHAR(50) NOT NULL,
        LoadedAtUtc         DATETIME2    NOT NULL CONSTRAINT DF_MatchRaw_LoadedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF OBJECT_ID(N'stg.InningsRaw', N'U') IS NULL
BEGIN
    CREATE TABLE stg.InningsRaw (
        MatchIdRaw          VARCHAR(50) NULL,
        InningsNo           TINYINT     NULL,
        BattingTeamCodeRaw  VARCHAR(10) NULL,
        BowlingTeamCodeRaw  VARCHAR(10) NULL,
        RunsScoredRaw       VARCHAR(10) NULL,
        WicketsLostRaw      VARCHAR(10) NULL,
        OversPlayedRaw      VARCHAR(10) NULL,
        ExtrasTotalRaw      VARCHAR(10) NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        SourceFileHash      CHAR(64)     NOT NULL,
        LoadRunId           VARCHAR(50) NOT NULL,
        LoadedAtUtc         DATETIME2    NOT NULL CONSTRAINT DF_InningsRaw_LoadedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF OBJECT_ID(N'stg.BallByBallRaw', N'U') IS NULL
BEGIN
    CREATE TABLE stg.BallByBallRaw (
        MatchIdRaw          VARCHAR(50) NULL,
        InningsNo           TINYINT     NULL,
        OverNo               INT         NULL,
        BallNo               INT         NULL,
        BatsmanCodeRaw       VARCHAR(20) NULL,
        BowlerCodeRaw        VARCHAR(20) NULL,
        RunsOffBatRaw        VARCHAR(10) NULL,
        ExtraRunsRaw         VARCHAR(10) NULL,
        ExtraTypeRaw         VARCHAR(20) NULL,
        WicketFlagRaw        VARCHAR(5)  NULL,
        DismissalTypeRaw     VARCHAR(30) NULL,
        DismissedPlayerCodeRaw VARCHAR(20) NULL,
        SourceFileName        VARCHAR(260) NOT NULL,
        SourceFileHash         CHAR(64)    NOT NULL,
        LoadRunId              VARCHAR(50) NOT NULL,
        LoadedAtUtc             DATETIME2  NOT NULL CONSTRAINT DF_BallByBallRaw_LoadedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF OBJECT_ID(N'stg.PlayerRankingRaw', N'U') IS NULL
BEGIN
    CREATE TABLE stg.PlayerRankingRaw (
        PlayerCodeRaw       VARCHAR(20) NULL,
        FormatCodeRaw       VARCHAR(10) NULL,
        DisciplineRaw       VARCHAR(20) NULL,   -- Batting / Bowling / AllRounder
        RankingDateRaw      VARCHAR(30) NULL,
        RankPositionRaw     VARCHAR(10) NULL,
        RatingPointsRaw     VARCHAR(10) NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        SourceFileHash      CHAR(64)     NOT NULL,
        LoadRunId           VARCHAR(50) NOT NULL,
        LoadedAtUtc         DATETIME2    NOT NULL CONSTRAINT DF_PlayerRankingRaw_LoadedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF OBJECT_ID(N'stg.HistoricalStatsRaw', N'U') IS NULL
BEGIN
    CREATE TABLE stg.HistoricalStatsRaw (
        PlayerCodeRaw       VARCHAR(20) NULL,
        SeasonRaw           VARCHAR(20) NULL,
        FormatCodeRaw       VARCHAR(10) NULL,
        MatchesPlayedRaw    VARCHAR(10) NULL,
        RunsScoredRaw       VARCHAR(10) NULL,
        WicketsTakenRaw     VARCHAR(10) NULL,
        SourceFileName      VARCHAR(260) NOT NULL,
        SourceFileHash      CHAR(64)     NOT NULL,
        LoadRunId           VARCHAR(50) NOT NULL,
        LoadedAtUtc         DATETIME2    NOT NULL CONSTRAINT DF_HistoricalStatsRaw_LoadedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

-- ===========================================================================
-- Dimensions
-- ===========================================================================

IF OBJECT_ID(N'dw.Dim_Date', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Dim_Date (
        DateKey         INT         NOT NULL PRIMARY KEY,   -- yyyymmdd
        FullDate        DATE        NOT NULL,
        [Year]          SMALLINT    NOT NULL,
        [Quarter]       TINYINT     NOT NULL,
        [Month]         TINYINT     NOT NULL,
        MonthName       VARCHAR(15) NOT NULL,
        [Day]           TINYINT     NOT NULL,
        DayOfWeekName   VARCHAR(15) NOT NULL,
        IsWeekend       BIT         NOT NULL,
        Season          VARCHAR(20) NULL
    );
END
GO

IF OBJECT_ID(N'dw.Dim_Team', N'U') IS NULL
BEGIN
    -- Type-2 SCD: one row per team version. TeamCode is the stable natural key across renames.
    CREATE TABLE dw.Dim_Team (
        TeamKey         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        TeamCode        VARCHAR(10)  NOT NULL,
        TeamName        VARCHAR(100) NOT NULL,
        Country         VARCHAR(50)  NULL,
        FoundedYear     INT          NULL,
        EffectiveFrom   DATE         NOT NULL,
        EffectiveTo     DATE         NULL,
        IsCurrent       BIT          NOT NULL CONSTRAINT DF_DimTeam_IsCurrent DEFAULT (1)
    );
    CREATE INDEX IX_DimTeam_TeamCode ON dw.Dim_Team (TeamCode, IsCurrent);
END
GO

IF OBJECT_ID(N'dw.Dim_Player', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Dim_Player (
        PlayerKey       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PlayerCode      VARCHAR(20)  NOT NULL,
        FullName        VARCHAR(150) NOT NULL,
        DateOfBirth     DATE         NULL,
        Country         VARCHAR(50)  NULL,
        BattingStyle    VARCHAR(30)  NULL,
        BowlingStyle    VARCHAR(30)  NULL,
        PlayerRole      VARCHAR(30)  NULL,
        DebutDate       DATE         NULL
    );
    CREATE UNIQUE INDEX UX_DimPlayer_PlayerCode ON dw.Dim_Player (PlayerCode);
END
GO

IF OBJECT_ID(N'dw.Dim_Venue', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Dim_Venue (
        VenueKey        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        VenueCode       VARCHAR(20)  NOT NULL,
        VenueName       VARCHAR(150) NOT NULL,
        City            VARCHAR(100) NULL,
        Country         VARCHAR(50)  NULL,
        Capacity        INT          NULL
    );
    CREATE UNIQUE INDEX UX_DimVenue_VenueCode ON dw.Dim_Venue (VenueCode);
END
GO

IF OBJECT_ID(N'dw.Dim_MatchFormat', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Dim_MatchFormat (
        FormatKey       TINYINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        FormatCode      VARCHAR(10) NOT NULL,   -- TEST / ODI / T20 / T10
        FormatName      VARCHAR(30) NOT NULL
    );
    CREATE UNIQUE INDEX UX_DimMatchFormat_Code ON dw.Dim_MatchFormat (FormatCode);
END
GO

IF OBJECT_ID(N'dw.Bridge_PlayerTeamSeason', N'U') IS NULL
BEGIN
    -- Models a player's team affiliation per season as a time-varying relationship,
    -- separate from Dim_Team's own Type-2 history of that team's identity.
    CREATE TABLE dw.Bridge_PlayerTeamSeason (
        PlayerKey       INT         NOT NULL,
        TeamKey         INT         NOT NULL,
        Season          VARCHAR(20) NOT NULL,
        CONSTRAINT PK_Bridge_PlayerTeamSeason PRIMARY KEY (PlayerKey, TeamKey, Season),
        CONSTRAINT FK_Bridge_Player FOREIGN KEY (PlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_Bridge_Team FOREIGN KEY (TeamKey) REFERENCES dw.Dim_Team (TeamKey)
    );
END
GO

-- ===========================================================================
-- Facts
-- ===========================================================================

IF OBJECT_ID(N'dw.Fact_MatchResult', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_MatchResult (
        MatchKey            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        MatchId              VARCHAR(50) NOT NULL,   -- natural key, parsed from source content
        DateKey               INT        NOT NULL,
        FormatKey             TINYINT    NOT NULL,
        VenueKey              INT        NOT NULL,
        Team1Key              INT        NOT NULL,
        Team2Key              INT        NOT NULL,
        TossWinnerTeamKey     INT        NULL,
        TossDecision          VARCHAR(10) NULL,       -- Bat / Field
        WinnerTeamKey         INT        NULL,        -- NULL is valid: no-result / abandoned
        ResultMethod          VARCHAR(15) NOT NULL,   -- Normal / Tied / NoResult / Abandoned / SuperOver
        WinMargin             INT        NULL,
        WinMarginType         VARCHAR(10) NULL,       -- Runs / Wickets
        ManOfMatchPlayerKey   INT        NULL,
        Season                VARCHAR(20) NOT NULL,
        SourceFileHash         CHAR(64)   NOT NULL,
        LoadRunId              VARCHAR(50) NOT NULL,
        CONSTRAINT FK_FactMatch_Date FOREIGN KEY (DateKey) REFERENCES dw.Dim_Date (DateKey),
        CONSTRAINT FK_FactMatch_Format FOREIGN KEY (FormatKey) REFERENCES dw.Dim_MatchFormat (FormatKey),
        CONSTRAINT FK_FactMatch_Venue FOREIGN KEY (VenueKey) REFERENCES dw.Dim_Venue (VenueKey),
        CONSTRAINT FK_FactMatch_Team1 FOREIGN KEY (Team1Key) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT FK_FactMatch_Team2 FOREIGN KEY (Team2Key) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT FK_FactMatch_TossWinner FOREIGN KEY (TossWinnerTeamKey) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT FK_FactMatch_Winner FOREIGN KEY (WinnerTeamKey) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT FK_FactMatch_MoM FOREIGN KEY (ManOfMatchPlayerKey) REFERENCES dw.Dim_Player (PlayerKey)
    );
    CREATE UNIQUE INDEX UX_FactMatch_MatchId ON dw.Fact_MatchResult (MatchId);
    CREATE INDEX IX_FactMatch_DateKey ON dw.Fact_MatchResult (DateKey);
    CREATE INDEX IX_FactMatch_Season ON dw.Fact_MatchResult (Season);
END
GO

IF OBJECT_ID(N'dw.Fact_Innings', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_Innings (
        MatchKey            INT     NOT NULL,
        InningsNo             TINYINT NOT NULL,
        BattingTeamKey        INT     NOT NULL,
        BowlingTeamKey        INT     NOT NULL,
        RunsScored             INT     NOT NULL,
        WicketsLost             TINYINT NOT NULL,
        OversPlayed              DECIMAL(5,1) NOT NULL,
        ExtrasTotal               INT     NOT NULL CONSTRAINT DF_FactInnings_Extras DEFAULT (0),
        CONSTRAINT PK_FactInnings PRIMARY KEY (MatchKey, InningsNo),
        CONSTRAINT FK_FactInnings_Match FOREIGN KEY (MatchKey) REFERENCES dw.Fact_MatchResult (MatchKey),
        CONSTRAINT FK_FactInnings_BattingTeam FOREIGN KEY (BattingTeamKey) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT FK_FactInnings_BowlingTeam FOREIGN KEY (BowlingTeamKey) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT CK_FactInnings_Wickets CHECK (WicketsLost BETWEEN 0 AND 10)
    );
END
GO

IF OBJECT_ID(N'dw.Fact_BattingPerformance', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_BattingPerformance (
        MatchKey        INT     NOT NULL,
        InningsNo         TINYINT NOT NULL,
        PlayerKey          INT     NOT NULL,
        TeamKey             INT     NOT NULL,
        RunsScored           INT     NOT NULL,
        BallsFaced            INT     NOT NULL,
        Fours                  TINYINT NOT NULL CONSTRAINT DF_Batting_Fours DEFAULT (0),
        Sixes                   TINYINT NOT NULL CONSTRAINT DF_Batting_Sixes DEFAULT (0),
        IsNotOut                 BIT     NOT NULL,
        DismissalType             VARCHAR(30) NULL,
        DismissedByPlayerKey       INT NULL,
        CONSTRAINT PK_FactBatting PRIMARY KEY (MatchKey, InningsNo, PlayerKey),
        CONSTRAINT FK_FactBatting_Match FOREIGN KEY (MatchKey, InningsNo) REFERENCES dw.Fact_Innings (MatchKey, InningsNo),
        CONSTRAINT FK_FactBatting_Player FOREIGN KEY (PlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_FactBatting_Team FOREIGN KEY (TeamKey) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT FK_FactBatting_Dismisser FOREIGN KEY (DismissedByPlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT CK_FactBatting_Runs CHECK (RunsScored >= 0)
    );
END
GO

IF OBJECT_ID(N'dw.Fact_BowlingPerformance', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_BowlingPerformance (
        MatchKey        INT     NOT NULL,
        InningsNo         TINYINT NOT NULL,
        PlayerKey          INT     NOT NULL,
        TeamKey             INT     NOT NULL,
        OversBowled           DECIMAL(4,1) NOT NULL,
        RunsConceded            INT     NOT NULL,
        Wickets                  TINYINT NOT NULL,
        Maidens                   TINYINT NOT NULL CONSTRAINT DF_Bowling_Maidens DEFAULT (0),
        CONSTRAINT PK_FactBowling PRIMARY KEY (MatchKey, InningsNo, PlayerKey),
        CONSTRAINT FK_FactBowling_Match FOREIGN KEY (MatchKey, InningsNo) REFERENCES dw.Fact_Innings (MatchKey, InningsNo),
        CONSTRAINT FK_FactBowling_Player FOREIGN KEY (PlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_FactBowling_Team FOREIGN KEY (TeamKey) REFERENCES dw.Dim_Team (TeamKey),
        CONSTRAINT CK_FactBowling_Wickets CHECK (Wickets BETWEEN 0 AND 10)
    );
END
GO

IF OBJECT_ID(N'dw.Fact_BallByBall', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_BallByBall (
        MatchKey        INT     NOT NULL,
        InningsNo         TINYINT NOT NULL,
        OverNo              TINYINT NOT NULL,
        BallNo               TINYINT NOT NULL,
        BatsmanPlayerKey       INT NOT NULL,
        BowlerPlayerKey         INT NOT NULL,
        RunsOffBat                TINYINT NOT NULL,
        ExtraRuns                  TINYINT NOT NULL CONSTRAINT DF_BBB_ExtraRuns DEFAULT (0),
        ExtraType                   VARCHAR(15) NULL,
        IsWicket                     BIT NOT NULL CONSTRAINT DF_BBB_IsWicket DEFAULT (0),
        DismissalType                 VARCHAR(30) NULL,
        DismissedPlayerKey              INT NULL,
        CONSTRAINT PK_FactBallByBall PRIMARY KEY (MatchKey, InningsNo, OverNo, BallNo),
        CONSTRAINT FK_BBB_Match FOREIGN KEY (MatchKey, InningsNo) REFERENCES dw.Fact_Innings (MatchKey, InningsNo),
        CONSTRAINT FK_BBB_Batsman FOREIGN KEY (BatsmanPlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_BBB_Bowler FOREIGN KEY (BowlerPlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_BBB_Dismissed FOREIGN KEY (DismissedPlayerKey) REFERENCES dw.Dim_Player (PlayerKey)
    );
    CREATE INDEX IX_BBB_MatchInnings ON dw.Fact_BallByBall (MatchKey, InningsNo);
END
GO

IF OBJECT_ID(N'dw.Fact_Partnership', N'U') IS NULL
BEGIN
    -- Derived from Fact_BallByBall: runs added between consecutive wicket falls.
    CREATE TABLE dw.Fact_Partnership (
        MatchKey        INT     NOT NULL,
        InningsNo         TINYINT NOT NULL,
        WicketNumber        TINYINT NOT NULL,   -- partnership ending at this wicket (or innings end)
        Player1Key            INT NOT NULL,
        Player2Key              INT NOT NULL,
        RunsAdded                 INT NOT NULL,
        BallsFaced                  INT NOT NULL,
        CONSTRAINT PK_FactPartnership PRIMARY KEY (MatchKey, InningsNo, WicketNumber),
        CONSTRAINT FK_Partnership_Match FOREIGN KEY (MatchKey, InningsNo) REFERENCES dw.Fact_Innings (MatchKey, InningsNo),
        CONSTRAINT FK_Partnership_Player1 FOREIGN KEY (Player1Key) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_Partnership_Player2 FOREIGN KEY (Player2Key) REFERENCES dw.Dim_Player (PlayerKey)
    );
END
GO

IF OBJECT_ID(N'dw.Fact_FallOfWicket', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_FallOfWicket (
        MatchKey        INT     NOT NULL,
        InningsNo         TINYINT NOT NULL,
        WicketNumber        TINYINT NOT NULL,
        ScoreAtFall            INT NOT NULL,
        OverAtFall               DECIMAL(4,1) NOT NULL,
        PlayerOutKey               INT NOT NULL,
        BowlerKey                    INT NULL,
        DismissalType                  VARCHAR(30) NOT NULL,
        CONSTRAINT PK_FactFallOfWicket PRIMARY KEY (MatchKey, InningsNo, WicketNumber),
        CONSTRAINT FK_FoW_Match FOREIGN KEY (MatchKey, InningsNo) REFERENCES dw.Fact_Innings (MatchKey, InningsNo),
        CONSTRAINT FK_FoW_PlayerOut FOREIGN KEY (PlayerOutKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_FoW_Bowler FOREIGN KEY (BowlerKey) REFERENCES dw.Dim_Player (PlayerKey)
    );
END
GO

IF OBJECT_ID(N'dw.Agg_OverSummary', N'U') IS NULL
BEGIN
    -- Pre-aggregated from Fact_BallByBall so nothing downstream aggregates ball-by-ball live.
    CREATE TABLE dw.Agg_OverSummary (
        MatchKey        INT     NOT NULL,
        InningsNo         TINYINT NOT NULL,
        OverNo              TINYINT NOT NULL,
        RunsInOver            TINYINT NOT NULL,
        WicketsInOver           TINYINT NOT NULL,
        CONSTRAINT PK_AggOverSummary PRIMARY KEY (MatchKey, InningsNo, OverNo),
        CONSTRAINT FK_AggOver_Match FOREIGN KEY (MatchKey, InningsNo) REFERENCES dw.Fact_Innings (MatchKey, InningsNo)
    );
END
GO

IF OBJECT_ID(N'dw.Fact_PlayerRanking', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_PlayerRanking (
        PlayerKey        INT     NOT NULL,
        FormatKey          TINYINT NOT NULL,
        RankingDate          DATE NOT NULL,
        Discipline             VARCHAR(20) NOT NULL,  -- Batting / Bowling / AllRounder
        RankPosition             SMALLINT NOT NULL,
        RatingPoints               SMALLINT NOT NULL,
        CONSTRAINT PK_FactPlayerRanking PRIMARY KEY (PlayerKey, FormatKey, RankingDate, Discipline),
        CONSTRAINT FK_Ranking_Player FOREIGN KEY (PlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_Ranking_Format FOREIGN KEY (FormatKey) REFERENCES dw.Dim_MatchFormat (FormatKey)
    );
END
GO
