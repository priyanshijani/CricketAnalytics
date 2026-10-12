-- CricketDW: warehouse load (workflow 05_transform_load).
--
-- Workflow 05 does the transformation in Alteryx - SCD2 change detection for Dim_Team, batting / bowling
-- aggregation, partnerships and fall of wicket from ball-by-ball, the over summary - and writes the results,
-- still keyed by natural codes, to the stg.LoadReady_* tables. It then calls dw.usp_PublishWarehouse, which
-- resolves surrogate keys and applies every change in ONE transaction: a failure anywhere rolls the whole
-- publish back, and the stg.*Valid queue is emptied only when the publish commits.
-- Idempotent: safe to re-run.

USE CricketDW;
GO

-- ===========================================================================
-- Structural changes to existing tables
-- ===========================================================================

-- Team names as they appear in each match file: the source of Dim_Team's Type-2 history
-- (CricketSource.Teams holds only the current name).
IF COL_LENGTH(N'stg.MatchRaw', N'Team1NameRaw') IS NULL
    ALTER TABLE stg.MatchRaw ADD Team1NameRaw VARCHAR(100) NULL, Team2NameRaw VARCHAR(100) NULL;
GO
IF COL_LENGTH(N'stg.MatchValid', N'Team1Name') IS NULL
    ALTER TABLE stg.MatchValid ADD Team1Name VARCHAR(100) NULL, Team2Name VARCHAR(100) NULL;
GO

-- Ball-by-ball records only the striker; a partner who never faced a ball cannot be identified.
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dw.Fact_Partnership') AND name = N'Player2Key' AND is_nullable = 0)
    ALTER TABLE dw.Fact_Partnership ALTER COLUMN Player2Key INT NULL;
GO

-- Match completeness from the DQ gate, so dashboards can flag or exclude incomplete matches.
IF COL_LENGTH(N'dw.Fact_MatchResult', N'InningsStatus') IS NULL
    ALTER TABLE dw.Fact_MatchResult ADD
        InningsStatus    VARCHAR(15) NULL,   -- Complete / Incomplete (an innings failed validation)
        BallByBallStatus VARCHAR(15) NULL;   -- Loaded / Held (ball-by-ball withheld for the whole match)
GO

IF OBJECT_ID(N'dw.Fact_PlayerSeasonStats', N'U') IS NULL
BEGIN
    CREATE TABLE dw.Fact_PlayerSeasonStats (
        PlayerKey       INT         NOT NULL,
        Season          VARCHAR(20) NOT NULL,
        FormatKey       TINYINT     NOT NULL,
        MatchesPlayed   INT         NOT NULL,
        RunsScored      INT         NOT NULL,
        WicketsTaken    INT         NOT NULL,
        CONSTRAINT PK_FactPlayerSeasonStats PRIMARY KEY (PlayerKey, Season, FormatKey),
        CONSTRAINT FK_SeasonStats_Player FOREIGN KEY (PlayerKey) REFERENCES dw.Dim_Player (PlayerKey),
        CONSTRAINT FK_SeasonStats_Format FOREIGN KEY (FormatKey) REFERENCES dw.Dim_MatchFormat (FormatKey)
    );
END
GO

IF OBJECT_ID(N'audit.Audit_PublishLog', N'U') IS NULL
BEGIN
    CREATE TABLE audit.Audit_PublishLog (
        PublishLogId    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        LoadRunId       VARCHAR(50)  NOT NULL,
        TableName       VARCHAR(60)  NOT NULL,
        Operation       VARCHAR(20)  NOT NULL,   -- Inserted / Updated / Deleted / Consumed
        RowsAffected    INT          NOT NULL,
        PublishedAtUtc  DATETIME2    NOT NULL CONSTRAINT DF_PublishLog_At DEFAULT (SYSUTCDATETIME())
    );
END
GO

-- ===========================================================================
-- Load tables: written by 05 each run (Delete & Append), natural codes only
-- ===========================================================================

IF OBJECT_ID(N'stg.LoadReady_DimMatchFormat', N'U') IS NULL
    CREATE TABLE stg.LoadReady_DimMatchFormat (FormatCode VARCHAR(10) NOT NULL, FormatName VARCHAR(30) NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_DimVenue', N'U') IS NULL
    CREATE TABLE stg.LoadReady_DimVenue (VenueCode VARCHAR(20) NOT NULL, VenueName VARCHAR(150) NOT NULL, City VARCHAR(100) NULL,
                                    Country VARCHAR(50) NULL, Capacity INT NULL);
IF OBJECT_ID(N'stg.LoadReady_DimPlayer', N'U') IS NULL
    CREATE TABLE stg.LoadReady_DimPlayer (PlayerCode VARCHAR(20) NOT NULL, FullName VARCHAR(150) NOT NULL, DateOfBirth DATE NULL,
                                     Country VARCHAR(50) NULL, BattingStyle VARCHAR(30) NULL, BowlingStyle VARCHAR(30) NULL,
                                     PlayerRole VARCHAR(30) NULL, DebutDate DATE NULL);
IF OBJECT_ID(N'stg.LoadReady_DimTeamVersion', N'U') IS NULL
    CREATE TABLE stg.LoadReady_DimTeamVersion (TeamCode VARCHAR(10) NOT NULL, TeamName VARCHAR(100) NOT NULL, Country VARCHAR(50) NULL,
                                          FoundedYear INT NULL, EffectiveFrom DATE NOT NULL, EffectiveTo DATE NULL, IsCurrent BIT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_Match', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Match (MatchId VARCHAR(50) NOT NULL, MatchDate DATE NOT NULL, DateKey INT NOT NULL, FormatCode VARCHAR(10) NOT NULL,
                                 VenueCode VARCHAR(20) NOT NULL, Team1Code VARCHAR(10) NOT NULL, Team2Code VARCHAR(10) NOT NULL,
                                 TossWinnerCode VARCHAR(10) NULL, TossDecision VARCHAR(10) NULL, WinnerCode VARCHAR(10) NULL,
                                 ResultMethod VARCHAR(15) NOT NULL, WinMargin INT NULL, WinMarginType VARCHAR(10) NULL,
                                 ManOfMatchCode VARCHAR(20) NULL, Season VARCHAR(20) NOT NULL, SourceFileHash CHAR(64) NOT NULL,
                                 FileStatus VARCHAR(15) NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_Innings', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Innings (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, BattingTeamCode VARCHAR(10) NOT NULL,
                                   BowlingTeamCode VARCHAR(10) NOT NULL, RunsScored INT NOT NULL, WicketsLost TINYINT NOT NULL,
                                   OversPlayed DECIMAL(5,1) NOT NULL, ExtrasTotal INT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_BallByBall', N'U') IS NULL
    CREATE TABLE stg.LoadReady_BallByBall (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, OverNo TINYINT NOT NULL, BallNo TINYINT NOT NULL,
                                      BatsmanCode VARCHAR(20) NOT NULL, BowlerCode VARCHAR(20) NOT NULL, RunsOffBat TINYINT NOT NULL,
                                      ExtraRuns TINYINT NOT NULL, ExtraType VARCHAR(15) NULL, IsWicket BIT NOT NULL,
                                      DismissalType VARCHAR(30) NULL, DismissedPlayerCode VARCHAR(20) NULL);
IF OBJECT_ID(N'stg.LoadReady_Batting', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Batting (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, PlayerCode VARCHAR(20) NOT NULL,
                                   RunsScored INT NOT NULL, BallsFaced INT NOT NULL, Fours TINYINT NOT NULL, Sixes TINYINT NOT NULL,
                                   IsNotOut BIT NOT NULL, DismissalType VARCHAR(30) NULL, DismissedByCode VARCHAR(20) NULL);
IF OBJECT_ID(N'stg.LoadReady_Bowling', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Bowling (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, PlayerCode VARCHAR(20) NOT NULL,
                                   OversBowled DECIMAL(4,1) NOT NULL, RunsConceded INT NOT NULL, Wickets TINYINT NOT NULL, Maidens TINYINT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_Partnership', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Partnership (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, WicketNumber TINYINT NOT NULL,
                                       Player1Code VARCHAR(20) NOT NULL, Player2Code VARCHAR(20) NULL, RunsAdded INT NOT NULL, BallsFaced INT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_FallOfWicket', N'U') IS NULL
    CREATE TABLE stg.LoadReady_FallOfWicket (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, WicketNumber TINYINT NOT NULL,
                                        ScoreAtFall INT NOT NULL, OverAtFall DECIMAL(4,1) NOT NULL, PlayerOutCode VARCHAR(20) NOT NULL,
                                        BowlerCode VARCHAR(20) NULL, DismissalType VARCHAR(30) NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_OverSummary', N'U') IS NULL
    CREATE TABLE stg.LoadReady_OverSummary (MatchId VARCHAR(50) NOT NULL, InningsNo TINYINT NOT NULL, OverNo TINYINT NOT NULL,
                                       RunsInOver TINYINT NOT NULL, WicketsInOver TINYINT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_MatchCompleteness', N'U') IS NULL
    CREATE TABLE stg.LoadReady_MatchCompleteness (MatchId VARCHAR(50) NOT NULL, InningsStatus VARCHAR(15) NULL, BallByBallStatus VARCHAR(15) NULL);
IF OBJECT_ID(N'stg.LoadReady_PlayerRanking', N'U') IS NULL
    CREATE TABLE stg.LoadReady_PlayerRanking (PlayerCode VARCHAR(20) NOT NULL, FormatCode VARCHAR(10) NOT NULL, RankingDate DATE NOT NULL,
                                         Discipline VARCHAR(20) NOT NULL, RankPosition SMALLINT NOT NULL, RatingPoints SMALLINT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_PlayerSeasonStats', N'U') IS NULL
    CREATE TABLE stg.LoadReady_PlayerSeasonStats (PlayerCode VARCHAR(20) NOT NULL, Season VARCHAR(20) NOT NULL, FormatCode VARCHAR(10) NOT NULL,
                                             MatchesPlayed INT NOT NULL, RunsScored INT NOT NULL, WicketsTaken INT NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_Consumed', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Consumed (QueueTable VARCHAR(60) NOT NULL, MaxLoadRunId VARCHAR(50) NOT NULL);
IF OBJECT_ID(N'stg.LoadReady_Control', N'U') IS NULL
    CREATE TABLE stg.LoadReady_Control (LoadRunId VARCHAR(50) NOT NULL, LoadRowsWritten INT NOT NULL);
GO

-- ===========================================================================
-- Publish: one transaction, all or nothing
-- ===========================================================================
CREATE OR ALTER PROCEDURE dw.usp_PublishWarehouse
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- any error rolls back the whole publish

    DECLARE @run VARCHAR(50) = (SELECT TOP (1) LoadRunId FROM stg.LoadReady_Control);
    IF @run IS NULL THROW 50001, 'stg.LoadReady_Control is empty - run workflow 05 to stage a load first.', 1;

    -- Every load row 05 sent must be present: guards against publishing a partly written load.
    IF (SELECT LoadRowsWritten FROM stg.LoadReady_Control) <> (SELECT COUNT(*) FROM stg.LoadReady_DimMatchFormat) + (SELECT COUNT(*) FROM stg.LoadReady_DimVenue) + (SELECT COUNT(*) FROM stg.LoadReady_DimPlayer) + (SELECT COUNT(*) FROM stg.LoadReady_DimTeamVersion) + (SELECT COUNT(*) FROM stg.LoadReady_Match) + (SELECT COUNT(*) FROM stg.LoadReady_Innings) + (SELECT COUNT(*) FROM stg.LoadReady_BallByBall) + (SELECT COUNT(*) FROM stg.LoadReady_Batting) + (SELECT COUNT(*) FROM stg.LoadReady_Bowling) + (SELECT COUNT(*) FROM stg.LoadReady_Partnership) + (SELECT COUNT(*) FROM stg.LoadReady_FallOfWicket) + (SELECT COUNT(*) FROM stg.LoadReady_OverSummary) + (SELECT COUNT(*) FROM stg.LoadReady_MatchCompleteness) + (SELECT COUNT(*) FROM stg.LoadReady_PlayerRanking) + (SELECT COUNT(*) FROM stg.LoadReady_PlayerSeasonStats) + (SELECT COUNT(*) FROM stg.LoadReady_Consumed)
        THROW 50010, 'Publish aborted: stg.LoadReady_* row counts do not match what workflow 05 wrote.', 1;

    DECLARE @log TABLE (TableName VARCHAR(60), Operation VARCHAR(20), RowsAffected INT);
    DECLARE @merge TABLE (act NVARCHAR(10));
    DECLARE @bad INT;

    BEGIN TRANSACTION;

    -- ---------------- Dimensions ----------------
    MERGE dw.Dim_MatchFormat AS t
    USING stg.LoadReady_DimMatchFormat AS s ON t.FormatCode = s.FormatCode
    WHEN MATCHED AND t.FormatName <> s.FormatName THEN UPDATE SET FormatName = s.FormatName
    WHEN NOT MATCHED THEN INSERT (FormatCode, FormatName) VALUES (s.FormatCode, s.FormatName)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Dim_MatchFormat', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    MERGE dw.Dim_Venue AS t
    USING stg.LoadReady_DimVenue AS s ON t.VenueCode = s.VenueCode
    WHEN MATCHED AND EXISTS (SELECT t.VenueName, t.City, t.Country, t.Capacity EXCEPT SELECT s.VenueName, s.City, s.Country, s.Capacity)
        THEN UPDATE SET VenueName = s.VenueName, City = s.City, Country = s.Country, Capacity = s.Capacity
    WHEN NOT MATCHED THEN INSERT (VenueCode, VenueName, City, Country, Capacity) VALUES (s.VenueCode, s.VenueName, s.City, s.Country, s.Capacity)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Dim_Venue', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    -- Type 1: attributes overwritten in place.
    MERGE dw.Dim_Player AS t
    USING stg.LoadReady_DimPlayer AS s ON t.PlayerCode = s.PlayerCode
    WHEN MATCHED AND EXISTS (SELECT t.FullName, t.DateOfBirth, t.Country, t.BattingStyle, t.BowlingStyle, t.PlayerRole, t.DebutDate
                             EXCEPT SELECT s.FullName, s.DateOfBirth, s.Country, s.BattingStyle, s.BowlingStyle, s.PlayerRole, s.DebutDate)
        THEN UPDATE SET FullName = s.FullName, DateOfBirth = s.DateOfBirth, Country = s.Country, BattingStyle = s.BattingStyle,
                        BowlingStyle = s.BowlingStyle, PlayerRole = s.PlayerRole, DebutDate = s.DebutDate
    WHEN NOT MATCHED THEN INSERT (PlayerCode, FullName, DateOfBirth, Country, BattingStyle, BowlingStyle, PlayerRole, DebutDate)
        VALUES (s.PlayerCode, s.FullName, s.DateOfBirth, s.Country, s.BattingStyle, s.BowlingStyle, s.PlayerRole, s.DebutDate)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Dim_Player', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    -- Type 2: 05 sends the full version list per team; a version is identified by (TeamCode, EffectiveFrom),
    -- so existing versions keep their TeamKey and only EffectiveTo / IsCurrent / Type-1 attributes change.
    MERGE dw.Dim_Team AS t
    USING stg.LoadReady_DimTeamVersion AS s ON t.TeamCode = s.TeamCode AND t.EffectiveFrom = s.EffectiveFrom
    WHEN MATCHED AND EXISTS (SELECT t.TeamName, t.Country, t.FoundedYear, t.EffectiveTo, t.IsCurrent
                             EXCEPT SELECT s.TeamName, s.Country, s.FoundedYear, s.EffectiveTo, s.IsCurrent)
        THEN UPDATE SET TeamName = s.TeamName, Country = s.Country, FoundedYear = s.FoundedYear, EffectiveTo = s.EffectiveTo, IsCurrent = s.IsCurrent
    WHEN NOT MATCHED THEN INSERT (TeamCode, TeamName, Country, FoundedYear, EffectiveFrom, EffectiveTo, IsCurrent)
        VALUES (s.TeamCode, s.TeamName, s.Country, s.FoundedYear, s.EffectiveFrom, s.EffectiveTo, s.IsCurrent)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Dim_Team', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    -- ---------------- Match facts: resolve surrogate keys ----------------
    -- Team keys are the Dim_Team version in effect on the match date.
    SELECT m.MatchId, m.DateKey, f.FormatKey, v.VenueKey,
           t1.TeamKey AS Team1Key, t2.TeamKey AS Team2Key, tw.TeamKey AS TossWinnerTeamKey, m.TossDecision,
           w.TeamKey AS WinnerTeamKey, m.ResultMethod, m.WinMargin, m.WinMarginType, p.PlayerKey AS ManOfMatchPlayerKey,
           m.Season, m.SourceFileHash, m.TossWinnerCode, m.WinnerCode, m.ManOfMatchCode
    INTO #match
    FROM stg.LoadReady_Match AS m
    LEFT JOIN dw.Dim_MatchFormat AS f ON f.FormatCode = m.FormatCode
    LEFT JOIN dw.Dim_Venue AS v ON v.VenueCode = m.VenueCode
    LEFT JOIN dw.Dim_Team AS t1 ON t1.TeamCode = m.Team1Code AND m.MatchDate BETWEEN t1.EffectiveFrom AND ISNULL(t1.EffectiveTo, '9999-12-31')
    LEFT JOIN dw.Dim_Team AS t2 ON t2.TeamCode = m.Team2Code AND m.MatchDate BETWEEN t2.EffectiveFrom AND ISNULL(t2.EffectiveTo, '9999-12-31')
    LEFT JOIN dw.Dim_Team AS tw ON tw.TeamCode = m.TossWinnerCode AND m.MatchDate BETWEEN tw.EffectiveFrom AND ISNULL(tw.EffectiveTo, '9999-12-31')
    LEFT JOIN dw.Dim_Team AS w  ON w.TeamCode = m.WinnerCode AND m.MatchDate BETWEEN w.EffectiveFrom AND ISNULL(w.EffectiveTo, '9999-12-31')
    LEFT JOIN dw.Dim_Player AS p ON p.PlayerCode = m.ManOfMatchCode;

    SELECT @bad = COUNT(*) FROM #match
    WHERE FormatKey IS NULL OR VenueKey IS NULL OR Team1Key IS NULL OR Team2Key IS NULL
       OR (TossWinnerCode IS NOT NULL AND TossWinnerTeamKey IS NULL) OR (WinnerCode IS NOT NULL AND WinnerTeamKey IS NULL)
       OR (ManOfMatchCode IS NOT NULL AND ManOfMatchPlayerKey IS NULL);
    IF @bad > 0 THROW 50002, 'Publish aborted: a match references a dimension member that does not exist.', 1;

    -- MatchKey is stable: a corrected match updates its row instead of getting a new key.
    MERGE dw.Fact_MatchResult AS t
    USING #match AS s ON t.MatchId = s.MatchId
    WHEN MATCHED THEN UPDATE SET DateKey = s.DateKey, FormatKey = s.FormatKey, VenueKey = s.VenueKey, Team1Key = s.Team1Key,
        Team2Key = s.Team2Key, TossWinnerTeamKey = s.TossWinnerTeamKey, TossDecision = s.TossDecision, WinnerTeamKey = s.WinnerTeamKey,
        ResultMethod = s.ResultMethod, WinMargin = s.WinMargin, WinMarginType = s.WinMarginType, ManOfMatchPlayerKey = s.ManOfMatchPlayerKey,
        Season = s.Season, SourceFileHash = s.SourceFileHash, LoadRunId = @run
    WHEN NOT MATCHED THEN INSERT (MatchId, DateKey, FormatKey, VenueKey, Team1Key, Team2Key, TossWinnerTeamKey, TossDecision, WinnerTeamKey,
                                  ResultMethod, WinMargin, WinMarginType, ManOfMatchPlayerKey, Season, SourceFileHash, LoadRunId)
        VALUES (s.MatchId, s.DateKey, s.FormatKey, s.VenueKey, s.Team1Key, s.Team2Key, s.TossWinnerTeamKey, s.TossDecision, s.WinnerTeamKey,
                s.ResultMethod, s.WinMargin, s.WinMarginType, s.ManOfMatchPlayerKey, s.Season, s.SourceFileHash, @run)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Fact_MatchResult', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    -- ---------------- Which matches get their ball-by-ball replaced or removed ----------------
    SELECT DISTINCT fm.MatchKey
    INTO #ballMatch
    FROM dw.Fact_MatchResult AS fm
    WHERE fm.MatchId IN (SELECT MatchId FROM stg.LoadReady_BallByBall
                         UNION SELECT MatchId FROM stg.LoadReady_MatchCompleteness WHERE BallByBallStatus = 'Held');

    -- Innings dropped from a corrected match file (their ball-by-ball goes with them).
    SELECT fi.MatchKey, fi.InningsNo
    INTO #goneInnings
    FROM dw.Fact_Innings AS fi
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = fi.MatchKey
    WHERE fm.MatchId IN (SELECT MatchId FROM stg.LoadReady_Match)
      AND NOT EXISTS (SELECT 1 FROM stg.LoadReady_Innings AS li WHERE li.MatchId = fm.MatchId AND li.InningsNo = fi.InningsNo);

    DELETE x FROM dw.Fact_Partnership x WHERE x.MatchKey IN (SELECT MatchKey FROM #ballMatch) OR EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Fact_Partnership', 'Deleted', @@ROWCOUNT);
    DELETE x FROM dw.Fact_FallOfWicket x WHERE x.MatchKey IN (SELECT MatchKey FROM #ballMatch) OR EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Fact_FallOfWicket', 'Deleted', @@ROWCOUNT);
    DELETE x FROM dw.Agg_OverSummary x WHERE x.MatchKey IN (SELECT MatchKey FROM #ballMatch) OR EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Agg_OverSummary', 'Deleted', @@ROWCOUNT);
    DELETE x FROM dw.Fact_BattingPerformance x WHERE x.MatchKey IN (SELECT MatchKey FROM #ballMatch) OR EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Fact_BattingPerformance', 'Deleted', @@ROWCOUNT);
    DELETE x FROM dw.Fact_BowlingPerformance x WHERE x.MatchKey IN (SELECT MatchKey FROM #ballMatch) OR EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Fact_BowlingPerformance', 'Deleted', @@ROWCOUNT);
    DELETE x FROM dw.Fact_BallByBall x WHERE x.MatchKey IN (SELECT MatchKey FROM #ballMatch) OR EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Fact_BallByBall', 'Deleted', @@ROWCOUNT);
    DELETE x FROM dw.Fact_Innings x WHERE EXISTS (SELECT 1 FROM #goneInnings g WHERE g.MatchKey = x.MatchKey AND g.InningsNo = x.InningsNo);
    INSERT INTO @log VALUES ('dw.Fact_Innings', 'Deleted', @@ROWCOUNT);

    -- ---------------- Innings ----------------
    SELECT fm.MatchKey, li.InningsNo, bt.TeamKey AS BattingTeamKey, bw.TeamKey AS BowlingTeamKey,
           li.RunsScored, li.WicketsLost, li.OversPlayed, li.ExtrasTotal
    INTO #innings
    FROM stg.LoadReady_Innings AS li
    JOIN stg.LoadReady_Match AS lm ON lm.MatchId = li.MatchId
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = li.MatchId
    LEFT JOIN dw.Dim_Team AS bt ON bt.TeamCode = li.BattingTeamCode AND lm.MatchDate BETWEEN bt.EffectiveFrom AND ISNULL(bt.EffectiveTo, '9999-12-31')
    LEFT JOIN dw.Dim_Team AS bw ON bw.TeamCode = li.BowlingTeamCode AND lm.MatchDate BETWEEN bw.EffectiveFrom AND ISNULL(bw.EffectiveTo, '9999-12-31');
    IF EXISTS (SELECT 1 FROM #innings WHERE BattingTeamKey IS NULL OR BowlingTeamKey IS NULL)
        THROW 50003, 'Publish aborted: an innings references a team that does not exist.', 1;
    IF (SELECT COUNT(*) FROM #innings) <> (SELECT COUNT(*) FROM stg.LoadReady_Innings)
        THROW 50004, 'Publish aborted: an innings has no match header in this load.', 1;

    MERGE dw.Fact_Innings AS t
    USING #innings AS s ON t.MatchKey = s.MatchKey AND t.InningsNo = s.InningsNo
    WHEN MATCHED THEN UPDATE SET BattingTeamKey = s.BattingTeamKey, BowlingTeamKey = s.BowlingTeamKey, RunsScored = s.RunsScored,
        WicketsLost = s.WicketsLost, OversPlayed = s.OversPlayed, ExtrasTotal = s.ExtrasTotal
    WHEN NOT MATCHED THEN INSERT (MatchKey, InningsNo, BattingTeamKey, BowlingTeamKey, RunsScored, WicketsLost, OversPlayed, ExtrasTotal)
        VALUES (s.MatchKey, s.InningsNo, s.BattingTeamKey, s.BowlingTeamKey, s.RunsScored, s.WicketsLost, s.OversPlayed, s.ExtrasTotal)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Fact_Innings', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    -- ---------------- Ball-by-ball and everything derived from it ----------------
    -- Every row must find its innings and players; a miss aborts the publish instead of dropping rows.
    SELECT fi.MatchKey, b.InningsNo, b.OverNo, b.BallNo, bat.PlayerKey AS BatsmanPlayerKey, bowl.PlayerKey AS BowlerPlayerKey,
           b.RunsOffBat, b.ExtraRuns, b.ExtraType, b.IsWicket, b.DismissalType, dis.PlayerKey AS DismissedPlayerKey, b.DismissedPlayerCode
    INTO #ball
    FROM stg.LoadReady_BallByBall AS b
    LEFT JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = b.MatchId
    LEFT JOIN dw.Fact_Innings AS fi ON fi.MatchKey = fm.MatchKey AND fi.InningsNo = b.InningsNo
    LEFT JOIN dw.Dim_Player AS bat ON bat.PlayerCode = b.BatsmanCode
    LEFT JOIN dw.Dim_Player AS bowl ON bowl.PlayerCode = b.BowlerCode
    LEFT JOIN dw.Dim_Player AS dis ON dis.PlayerCode = b.DismissedPlayerCode;
    IF EXISTS (SELECT 1 FROM #ball WHERE MatchKey IS NULL OR BatsmanPlayerKey IS NULL OR BowlerPlayerKey IS NULL
                                      OR (DismissedPlayerCode IS NOT NULL AND DismissedPlayerKey IS NULL))
        THROW 50005, 'Publish aborted: a delivery has no innings in the warehouse or references an unknown player.', 1;

    INSERT INTO dw.Fact_BallByBall (MatchKey, InningsNo, OverNo, BallNo, BatsmanPlayerKey, BowlerPlayerKey, RunsOffBat, ExtraRuns,
                                    ExtraType, IsWicket, DismissalType, DismissedPlayerKey)
    SELECT MatchKey, InningsNo, OverNo, BallNo, BatsmanPlayerKey, BowlerPlayerKey, RunsOffBat, ExtraRuns, ExtraType, IsWicket,
           DismissalType, DismissedPlayerKey
    FROM #ball;
    INSERT INTO @log VALUES ('dw.Fact_BallByBall', 'Inserted', @@ROWCOUNT);

    INSERT INTO dw.Fact_BattingPerformance (MatchKey, InningsNo, PlayerKey, TeamKey, RunsScored, BallsFaced, Fours, Sixes, IsNotOut,
                                            DismissalType, DismissedByPlayerKey)
    SELECT fi.MatchKey, s.InningsNo, p.PlayerKey, fi.BattingTeamKey, s.RunsScored, s.BallsFaced, s.Fours, s.Sixes, s.IsNotOut,
           s.DismissalType, d.PlayerKey
    FROM stg.LoadReady_Batting AS s
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = s.MatchId
    JOIN dw.Fact_Innings AS fi ON fi.MatchKey = fm.MatchKey AND fi.InningsNo = s.InningsNo
    JOIN dw.Dim_Player AS p ON p.PlayerCode = s.PlayerCode
    LEFT JOIN dw.Dim_Player AS d ON d.PlayerCode = s.DismissedByCode;
    INSERT INTO @log VALUES ('dw.Fact_BattingPerformance', 'Inserted', @@ROWCOUNT);
    IF (SELECT RowsAffected FROM @log WHERE TableName = 'dw.Fact_BattingPerformance' AND Operation = 'Inserted') <> (SELECT COUNT(*) FROM stg.LoadReady_Batting)
        THROW 50006, 'Publish aborted: batting rows did not all resolve to an innings and player.', 1;

    INSERT INTO dw.Fact_BowlingPerformance (MatchKey, InningsNo, PlayerKey, TeamKey, OversBowled, RunsConceded, Wickets, Maidens)
    SELECT fi.MatchKey, s.InningsNo, p.PlayerKey, fi.BowlingTeamKey, s.OversBowled, s.RunsConceded, s.Wickets, s.Maidens
    FROM stg.LoadReady_Bowling AS s
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = s.MatchId
    JOIN dw.Fact_Innings AS fi ON fi.MatchKey = fm.MatchKey AND fi.InningsNo = s.InningsNo
    JOIN dw.Dim_Player AS p ON p.PlayerCode = s.PlayerCode;
    INSERT INTO @log VALUES ('dw.Fact_BowlingPerformance', 'Inserted', @@ROWCOUNT);
    IF (SELECT RowsAffected FROM @log WHERE TableName = 'dw.Fact_BowlingPerformance' AND Operation = 'Inserted') <> (SELECT COUNT(*) FROM stg.LoadReady_Bowling)
        THROW 50007, 'Publish aborted: bowling rows did not all resolve to an innings and player.', 1;

    INSERT INTO dw.Fact_Partnership (MatchKey, InningsNo, WicketNumber, Player1Key, Player2Key, RunsAdded, BallsFaced)
    SELECT fi.MatchKey, s.InningsNo, s.WicketNumber, p1.PlayerKey, p2.PlayerKey, s.RunsAdded, s.BallsFaced
    FROM stg.LoadReady_Partnership AS s
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = s.MatchId
    JOIN dw.Fact_Innings AS fi ON fi.MatchKey = fm.MatchKey AND fi.InningsNo = s.InningsNo
    JOIN dw.Dim_Player AS p1 ON p1.PlayerCode = s.Player1Code
    LEFT JOIN dw.Dim_Player AS p2 ON p2.PlayerCode = s.Player2Code;
    INSERT INTO @log VALUES ('dw.Fact_Partnership', 'Inserted', @@ROWCOUNT);

    INSERT INTO dw.Fact_FallOfWicket (MatchKey, InningsNo, WicketNumber, ScoreAtFall, OverAtFall, PlayerOutKey, BowlerKey, DismissalType)
    SELECT fi.MatchKey, s.InningsNo, s.WicketNumber, s.ScoreAtFall, s.OverAtFall, po.PlayerKey, bw.PlayerKey, s.DismissalType
    FROM stg.LoadReady_FallOfWicket AS s
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = s.MatchId
    JOIN dw.Fact_Innings AS fi ON fi.MatchKey = fm.MatchKey AND fi.InningsNo = s.InningsNo
    JOIN dw.Dim_Player AS po ON po.PlayerCode = s.PlayerOutCode
    LEFT JOIN dw.Dim_Player AS bw ON bw.PlayerCode = s.BowlerCode;
    INSERT INTO @log VALUES ('dw.Fact_FallOfWicket', 'Inserted', @@ROWCOUNT);

    INSERT INTO dw.Agg_OverSummary (MatchKey, InningsNo, OverNo, RunsInOver, WicketsInOver)
    SELECT fi.MatchKey, s.InningsNo, s.OverNo, s.RunsInOver, s.WicketsInOver
    FROM stg.LoadReady_OverSummary AS s
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = s.MatchId
    JOIN dw.Fact_Innings AS fi ON fi.MatchKey = fm.MatchKey AND fi.InningsNo = s.InningsNo;
    INSERT INTO @log VALUES ('dw.Agg_OverSummary', 'Inserted', @@ROWCOUNT);

    IF (SELECT SUM(RowsAffected) FROM @log WHERE Operation = 'Inserted' AND TableName IN ('dw.Fact_Partnership', 'dw.Fact_FallOfWicket', 'dw.Agg_OverSummary'))
       <> (SELECT (SELECT COUNT(*) FROM stg.LoadReady_Partnership) + (SELECT COUNT(*) FROM stg.LoadReady_FallOfWicket) + (SELECT COUNT(*) FROM stg.LoadReady_OverSummary))
        THROW 50008, 'Publish aborted: partnership / fall-of-wicket / over-summary rows did not all resolve.', 1;

    -- ---------------- Match completeness (NULL = not evaluated this run, keep the previous value) ----------------
    UPDATE fm
    SET InningsStatus = ISNULL(c.InningsStatus, fm.InningsStatus),
        BallByBallStatus = ISNULL(c.BallByBallStatus, fm.BallByBallStatus)
    FROM dw.Fact_MatchResult AS fm
    JOIN stg.LoadReady_MatchCompleteness AS c ON c.MatchId = fm.MatchId;
    INSERT INTO @log VALUES ('dw.Fact_MatchResult', 'StatusUpdated', @@ROWCOUNT);

    -- ---------------- Bridge: player x team version x season, from the loaded batting / bowling facts ----------------
    INSERT INTO dw.Bridge_PlayerTeamSeason (PlayerKey, TeamKey, Season)
    SELECT DISTINCT x.PlayerKey, x.TeamKey, fm.Season
    FROM (SELECT MatchKey, PlayerKey, TeamKey FROM dw.Fact_BattingPerformance
          UNION SELECT MatchKey, PlayerKey, TeamKey FROM dw.Fact_BowlingPerformance) AS x
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = x.MatchKey
    WHERE fm.MatchKey IN (SELECT MatchKey FROM #ballMatch)
      AND NOT EXISTS (SELECT 1 FROM dw.Bridge_PlayerTeamSeason AS b WHERE b.PlayerKey = x.PlayerKey AND b.TeamKey = x.TeamKey AND b.Season = fm.Season);
    INSERT INTO @log VALUES ('dw.Bridge_PlayerTeamSeason', 'Inserted', @@ROWCOUNT);

    -- ---------------- Player-level facts ----------------
    MERGE dw.Fact_PlayerRanking AS t
    USING (SELECT p.PlayerKey, f.FormatKey, s.RankingDate, s.Discipline, s.RankPosition, s.RatingPoints
           FROM stg.LoadReady_PlayerRanking AS s
           JOIN dw.Dim_Player AS p ON p.PlayerCode = s.PlayerCode
           JOIN dw.Dim_MatchFormat AS f ON f.FormatCode = s.FormatCode) AS s
    ON t.PlayerKey = s.PlayerKey AND t.FormatKey = s.FormatKey AND t.RankingDate = s.RankingDate AND t.Discipline = s.Discipline
    WHEN MATCHED AND (t.RankPosition <> s.RankPosition OR t.RatingPoints <> s.RatingPoints)
        THEN UPDATE SET RankPosition = s.RankPosition, RatingPoints = s.RatingPoints
    WHEN NOT MATCHED THEN INSERT (PlayerKey, FormatKey, RankingDate, Discipline, RankPosition, RatingPoints)
        VALUES (s.PlayerKey, s.FormatKey, s.RankingDate, s.Discipline, s.RankPosition, s.RatingPoints)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Fact_PlayerRanking', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    MERGE dw.Fact_PlayerSeasonStats AS t
    USING (SELECT p.PlayerKey, s.Season, f.FormatKey, s.MatchesPlayed, s.RunsScored, s.WicketsTaken
           FROM stg.LoadReady_PlayerSeasonStats AS s
           JOIN dw.Dim_Player AS p ON p.PlayerCode = s.PlayerCode
           JOIN dw.Dim_MatchFormat AS f ON f.FormatCode = s.FormatCode) AS s
    ON t.PlayerKey = s.PlayerKey AND t.Season = s.Season AND t.FormatKey = s.FormatKey
    WHEN MATCHED AND (t.MatchesPlayed <> s.MatchesPlayed OR t.RunsScored <> s.RunsScored OR t.WicketsTaken <> s.WicketsTaken)
        THEN UPDATE SET MatchesPlayed = s.MatchesPlayed, RunsScored = s.RunsScored, WicketsTaken = s.WicketsTaken
    WHEN NOT MATCHED THEN INSERT (PlayerKey, Season, FormatKey, MatchesPlayed, RunsScored, WicketsTaken)
        VALUES (s.PlayerKey, s.Season, s.FormatKey, s.MatchesPlayed, s.RunsScored, s.WicketsTaken)
    OUTPUT $action INTO @merge;
    INSERT INTO @log SELECT 'dw.Fact_PlayerSeasonStats', IIF(act = 'INSERT', 'Inserted', 'Updated'), COUNT(*) FROM @merge GROUP BY act;
    DELETE FROM @merge;

    IF (SELECT ISNULL(SUM(RowsAffected), 0) FROM @log WHERE TableName IN ('dw.Fact_PlayerRanking', 'dw.Fact_PlayerSeasonStats')) >
       (SELECT (SELECT COUNT(*) FROM stg.LoadReady_PlayerRanking) + (SELECT COUNT(*) FROM stg.LoadReady_PlayerSeasonStats))
        THROW 50009, 'Publish aborted: unexpected ranking / season-stats row count.', 1;

    -- ---------------- Consume the queue: only what 05 read, only now that everything succeeded ----------------
    DELETE q FROM stg.MatchValid q JOIN stg.LoadReady_Consumed c ON c.QueueTable = 'stg.MatchValid' WHERE q.LoadRunId <= c.MaxLoadRunId;
    INSERT INTO @log VALUES ('stg.MatchValid', 'Consumed', @@ROWCOUNT);
    DELETE q FROM stg.InningsValid q JOIN stg.LoadReady_Consumed c ON c.QueueTable = 'stg.InningsValid' WHERE q.LoadRunId <= c.MaxLoadRunId;
    INSERT INTO @log VALUES ('stg.InningsValid', 'Consumed', @@ROWCOUNT);
    DELETE q FROM stg.BallByBallValid q JOIN stg.LoadReady_Consumed c ON c.QueueTable = 'stg.BallByBallValid' WHERE q.LoadRunId <= c.MaxLoadRunId;
    INSERT INTO @log VALUES ('stg.BallByBallValid', 'Consumed', @@ROWCOUNT);
    DELETE q FROM stg.PlayerRankingValid q JOIN stg.LoadReady_Consumed c ON c.QueueTable = 'stg.PlayerRankingValid' WHERE q.LoadRunId <= c.MaxLoadRunId;
    INSERT INTO @log VALUES ('stg.PlayerRankingValid', 'Consumed', @@ROWCOUNT);
    DELETE q FROM stg.HistoricalStatsValid q JOIN stg.LoadReady_Consumed c ON c.QueueTable = 'stg.HistoricalStatsValid' WHERE q.LoadRunId <= c.MaxLoadRunId;
    INSERT INTO @log VALUES ('stg.HistoricalStatsValid', 'Consumed', @@ROWCOUNT);
    DELETE q FROM stg.MatchCompletenessValid q JOIN stg.LoadReady_Consumed c ON c.QueueTable = 'stg.MatchCompletenessValid' WHERE q.LoadRunId <= c.MaxLoadRunId;
    INSERT INTO @log VALUES ('stg.MatchCompletenessValid', 'Consumed', @@ROWCOUNT);

    INSERT INTO audit.Audit_PublishLog (LoadRunId, TableName, Operation, RowsAffected)
    SELECT @run, TableName, Operation, RowsAffected FROM @log WHERE RowsAffected > 0;

    -- The load has been applied: clear it so a later run can never re-publish it (DELETE, not TRUNCATE,
    -- so the least-privilege ETL login needs no ALTER permission).
    DELETE FROM stg.LoadReady_DimMatchFormat;
    DELETE FROM stg.LoadReady_DimVenue;
    DELETE FROM stg.LoadReady_DimPlayer;
    DELETE FROM stg.LoadReady_DimTeamVersion;
    DELETE FROM stg.LoadReady_Match;
    DELETE FROM stg.LoadReady_Innings;
    DELETE FROM stg.LoadReady_BallByBall;
    DELETE FROM stg.LoadReady_Batting;
    DELETE FROM stg.LoadReady_Bowling;
    DELETE FROM stg.LoadReady_Partnership;
    DELETE FROM stg.LoadReady_FallOfWicket;
    DELETE FROM stg.LoadReady_OverSummary;
    DELETE FROM stg.LoadReady_MatchCompleteness;
    DELETE FROM stg.LoadReady_PlayerRanking;
    DELETE FROM stg.LoadReady_PlayerSeasonStats;
    DELETE FROM stg.LoadReady_Consumed;
    DELETE FROM stg.LoadReady_Control;

    COMMIT TRANSACTION;
END
GO
