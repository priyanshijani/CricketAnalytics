-- CricketDW: metadata-driven data-quality framework used by Alteryx workflow 04_dq_validation.
--
-- config.DQEntity  - one row per validated entity: its staging table, natural-key and source-file
--                    expressions, and (for CSV entities) the expected header line.
-- config.DQRule    - one row per rule. EvaluatedBy = 'SQL' rules hold a T-SQL predicate over alias r
--                    (the entity's staging table); true means the row violates the rule. ActionTaken
--                    decides what 04 does: Rejected (row kept out of stg.*Valid), Flagged (logged,
--                    row loads), Defaulted (logged, offending value loaded as NULL).
--                    EvaluatedBy = 'Workflow' rules depend on this run's results (cascades) or on reading
--                    the file itself, so 04 evaluates them; the row still sets their ActionTaken.
--                    HoldsBallByBall = 1: a violation holds back every delivery of that match (the match
--                    is the unit of acceptance for ball-by-ball). ScopePredicate overrides the default
--                    incremental scope. RootCauseCategory / RemediationHint feed workflow 04b's reports.
-- config.vw_DQRuleSql - builds one runnable SELECT per active SQL rule. 04 runs each one through the
--                    DQ_RunRules batch macro. Rules only scan rows from files whose content hash is not
--                    yet in audit.Audit_FileControl (incremental validation); master data is always checked.
--
-- To add or change a rule: edit the MERGE below and re-run this script (the script is the source of
-- truth - re-running overwrites ad hoc edits to existing rules). No workflow change is needed.
-- Idempotent: safe to re-run.

USE CricketDW;
GO

-- Row identity on every validated staging table, so a rule can name the exact row it failed.
IF COL_LENGTH(N'stg.MatchRaw', N'StgRowId') IS NULL
    ALTER TABLE stg.MatchRaw ADD StgRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MatchRaw PRIMARY KEY NONCLUSTERED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MatchRaw_File' AND object_id = OBJECT_ID(N'stg.MatchRaw'))
    CREATE INDEX IX_MatchRaw_File ON stg.MatchRaw (SourceFileHash, SourceFileName);
GO
IF COL_LENGTH(N'stg.InningsRaw', N'StgRowId') IS NULL
    ALTER TABLE stg.InningsRaw ADD StgRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InningsRaw PRIMARY KEY NONCLUSTERED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_InningsRaw_File' AND object_id = OBJECT_ID(N'stg.InningsRaw'))
    CREATE INDEX IX_InningsRaw_File ON stg.InningsRaw (SourceFileHash, SourceFileName);
GO
IF COL_LENGTH(N'stg.BallByBallRaw', N'StgRowId') IS NULL
    ALTER TABLE stg.BallByBallRaw ADD StgRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BallByBallRaw PRIMARY KEY NONCLUSTERED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BallByBallRaw_File' AND object_id = OBJECT_ID(N'stg.BallByBallRaw'))
    CREATE INDEX IX_BallByBallRaw_File ON stg.BallByBallRaw (SourceFileHash, SourceFileName);
GO
IF COL_LENGTH(N'stg.PlayerRankingRaw', N'StgRowId') IS NULL
    ALTER TABLE stg.PlayerRankingRaw ADD StgRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlayerRankingRaw PRIMARY KEY NONCLUSTERED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PlayerRankingRaw_File' AND object_id = OBJECT_ID(N'stg.PlayerRankingRaw'))
    CREATE INDEX IX_PlayerRankingRaw_File ON stg.PlayerRankingRaw (SourceFileHash, SourceFileName);
GO
IF COL_LENGTH(N'stg.HistoricalStatsRaw', N'StgRowId') IS NULL
    ALTER TABLE stg.HistoricalStatsRaw ADD StgRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_HistoricalStatsRaw PRIMARY KEY NONCLUSTERED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_HistoricalStatsRaw_File' AND object_id = OBJECT_ID(N'stg.HistoricalStatsRaw'))
    CREATE INDEX IX_HistoricalStatsRaw_File ON stg.HistoricalStatsRaw (SourceFileHash, SourceFileName);
GO
IF COL_LENGTH(N'stg.PlayersSnapshot', N'StgRowId') IS NULL
    ALTER TABLE stg.PlayersSnapshot ADD StgRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlayersSnapshot PRIMARY KEY NONCLUSTERED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BallByBallRaw_Key' AND object_id = OBJECT_ID(N'stg.BallByBallRaw'))
    CREATE INDEX IX_BallByBallRaw_Key ON stg.BallByBallRaw (MatchIdRaw, InningsNo, OverNo, BallNo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FileControl_FileName' AND object_id = OBJECT_ID(N'audit.Audit_FileControl'))
    CREATE INDEX IX_FileControl_FileName ON audit.Audit_FileControl (FileName, Status);
GO

IF OBJECT_ID(N'config.DQEntity', N'U') IS NULL
BEGIN
    CREATE TABLE config.DQEntity (
        EntityType      VARCHAR(30)   NOT NULL PRIMARY KEY,
        StagingTable    VARCHAR(128)  NULL,
        NaturalKeyExpr  NVARCHAR(400) NULL,      -- T-SQL over alias r
        SourceFileExpr  NVARCHAR(200) NULL,      -- T-SQL over alias r
        SourceType      VARCHAR(10)   NOT NULL,  -- JSON / CSV / SQL
        IsFileBased     BIT           NOT NULL,  -- 1 = validate only rows from new/changed files
        ExpectedHeader  VARCHAR(1000) NULL,      -- CSV entities: exact header line (CSV_SCHEMA.md)
        ValidTable      VARCHAR(128)  NULL,
        OwnerCode       VARCHAR(40)   NULL,      -- who fixes this entity's issues (file-name safe)
        OwnerName       VARCHAR(100)  NULL
    );
END
GO
IF COL_LENGTH(N'config.DQEntity', N'OwnerCode') IS NULL
    ALTER TABLE config.DQEntity ADD OwnerCode VARCHAR(40) NULL, OwnerName VARCHAR(100) NULL;
GO

IF OBJECT_ID(N'config.DQRule', N'U') IS NULL
BEGIN
    CREATE TABLE config.DQRule (
        RuleId          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        EntityType      VARCHAR(30)   NOT NULL REFERENCES config.DQEntity (EntityType),
        RuleCode        VARCHAR(100)  NOT NULL,  -- written to Audit_DQException.RuleViolated
        Dimension       VARCHAR(20)   NOT NULL,  -- Completeness / Validity / Uniqueness / Integrity / Consistency / Conformity
        ActionTaken     VARCHAR(20)   NOT NULL CONSTRAINT CK_DQRule_Action CHECK (ActionTaken IN ('Rejected','Flagged','Defaulted')),
        EvaluatedBy     VARCHAR(10)   NOT NULL CONSTRAINT CK_DQRule_EvaluatedBy CHECK (EvaluatedBy IN ('SQL','Workflow')),
        RulePredicate   NVARCHAR(MAX) NULL,      -- SQL rules: true = violation
        RawValueExpr    NVARCHAR(MAX) NULL,      -- SQL rules: offending value written to RawValue
        PlantedIssue    VARCHAR(10)   NULL,      -- DQnn reference in DATA_QUALITY_ISSUES.md
        Description     VARCHAR(300)  NOT NULL,
        IsActive        BIT           NOT NULL CONSTRAINT DF_DQRule_IsActive DEFAULT (1),
        HoldsBallByBall BIT           NOT NULL CONSTRAINT DF_DQRule_HoldsBallByBall DEFAULT (0),  -- 1 = a violation holds back every delivery of that match
        ScopePredicate  NVARCHAR(MAX) NULL,      -- SQL rules: replaces the default "file not yet processed" scope
        RootCauseCategory VARCHAR(40) NULL,      -- feedback loop: why this class of issue happens
        RemediationHint VARCHAR(300)  NULL,      -- feedback loop: what the owner should do
        CONSTRAINT UQ_DQRule UNIQUE (EntityType, RuleCode),
        CONSTRAINT CK_DQRule_SqlHasPredicate CHECK (EvaluatedBy = 'Workflow' OR (RulePredicate IS NOT NULL AND RawValueExpr IS NOT NULL))
    );
END
GO
IF COL_LENGTH(N'config.DQRule', N'HoldsBallByBall') IS NULL
    ALTER TABLE config.DQRule ADD
        HoldsBallByBall BIT NOT NULL CONSTRAINT DF_DQRule_HoldsBallByBall DEFAULT (0),
        ScopePredicate NVARCHAR(MAX) NULL,
        RootCauseCategory VARCHAR(40) NULL,
        RemediationHint VARCHAR(300) NULL;
GO

MERGE config.DQEntity AS t
USING (VALUES
        (N'Match', N'stg.MatchRaw', N'COALESCE(r.MatchIdRaw, r.SourceFileName)', N'r.SourceFileName', N'JSON', 1, NULL, N'stg.MatchValid', N'match_data_provider', N'Match data provider (JSON scorecards)'),
        (N'Innings', N'stg.InningsRaw', N'CONCAT(r.MatchIdRaw, ''|'', r.InningsNo + 1)', N'r.SourceFileName', N'JSON', 1, NULL, N'stg.InningsValid', N'match_data_provider', N'Match data provider (JSON scorecards)'),
        (N'Delivery', N'stg.BallByBallRaw', N'CONCAT(r.MatchIdRaw, ''|'', r.InningsNo, ''|'', r.OverNo, ''|'', r.BallNo)', N'r.SourceFileName', N'CSV', 1, N'match_id,innings_no,over_no,ball_no,batsman_code,bowler_code,runs_off_bat,extra_runs,extra_type,is_wicket,dismissal_type,dismissed_player_code', N'stg.BallByBallValid', N'ballbyball_provider', N'Ball-by-ball provider (deliveries CSV)'),
        (N'PlayerRanking', N'stg.PlayerRankingRaw', N'CONCAT(r.PlayerCodeRaw, ''|'', r.FormatCodeRaw, ''|'', r.DisciplineRaw, ''|'', r.RankingDateRaw)', N'r.SourceFileName', N'CSV', 1, N'player_code,player_name,format_code,discipline,ranking_date,rank_position,rating_points', N'stg.PlayerRankingValid', N'player_stats_provider', N'Player statistics provider (rankings / historical CSV)'),
        (N'HistoricalStats', N'stg.HistoricalStatsRaw', N'CONCAT(r.PlayerCodeRaw, ''|'', r.SeasonRaw, ''|'', r.FormatCodeRaw)', N'r.SourceFileName', N'CSV', 1, N'player_code,player_name,season,format_code,matches_played,runs_scored,wickets_taken,season_start_date', N'stg.HistoricalStatsValid', N'player_stats_provider', N'Player statistics provider (rankings / historical CSV)'),
        (N'Player', N'stg.PlayersSnapshot', N'r.PlayerCode', N'''CricketSource.dbo.Players''', N'SQL', 0, NULL, N'stg.PlayersValid', N'master_data_steward', N'Master data steward (CricketSource)'),
        (N'File', NULL, NULL, NULL, N'CSV', 1, NULL, NULL, N'csv_file_provider', N'CSV file provider (any CSV feed)')
    ) AS s (EntityType, StagingTable, NaturalKeyExpr, SourceFileExpr, SourceType, IsFileBased, ExpectedHeader, ValidTable, OwnerCode, OwnerName)
ON t.EntityType = s.EntityType
WHEN MATCHED THEN UPDATE SET StagingTable = s.StagingTable, NaturalKeyExpr = s.NaturalKeyExpr, SourceFileExpr = s.SourceFileExpr,
    SourceType = s.SourceType, IsFileBased = s.IsFileBased, ExpectedHeader = s.ExpectedHeader, ValidTable = s.ValidTable,
    OwnerCode = s.OwnerCode, OwnerName = s.OwnerName
WHEN NOT MATCHED THEN INSERT (EntityType, StagingTable, NaturalKeyExpr, SourceFileExpr, SourceType, IsFileBased, ExpectedHeader, ValidTable, OwnerCode, OwnerName)
    VALUES (s.EntityType, s.StagingTable, s.NaturalKeyExpr, s.SourceFileExpr, s.SourceType, s.IsFileBased, s.ExpectedHeader, s.ValidTable, s.OwnerCode, s.OwnerName);
GO

MERGE config.DQRule AS t
USING (VALUES
        (N'Match', N'missing_match_identity', N'Completeness', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.MatchIdRaw), '''') IS NULL', N'''match_id is empty''', N'DQ12', N'JSON file has no match_id', 0, NULL, N'File delivery / format', N'Populate match_id and re-send the file.'),
        (N'Match', N'missing_required_field', N'Completeness', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.MatchDateRaw), '''') IS NULL OR NULLIF(LTRIM(r.FormatCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.Team1CodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.Team2CodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.VenueCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.ResultMethodRaw), '''') IS NULL', N'CONCAT(''missing:'', IIF(NULLIF(LTRIM(r.MatchDateRaw), '''') IS NULL, '' MatchDateRaw'', ''''), IIF(NULLIF(LTRIM(r.FormatCodeRaw), '''') IS NULL, '' FormatCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.Team1CodeRaw), '''') IS NULL, '' Team1CodeRaw'', ''''), IIF(NULLIF(LTRIM(r.Team2CodeRaw), '''') IS NULL, '' Team2CodeRaw'', ''''), IIF(NULLIF(LTRIM(r.VenueCodeRaw), '''') IS NULL, '' VenueCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.ResultMethodRaw), '''') IS NULL, '' ResultMethodRaw'', ''''))', N'DQ11', N'Required match header field is empty', 0, NULL, N'Source data entry', N'Populate the missing fields and re-send the file.'),
        (N'Match', N'invalid_date', N'Validity', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.MatchDateRaw), '''') IS NOT NULL AND TRY_CONVERT(date, r.MatchDateRaw, 23) IS NULL', N'r.MatchDateRaw', NULL, N'match_date is not yyyy-mm-dd', 0, NULL, N'Source data entry', N'Correct the date to its documented format and re-send the file.'),
        (N'Match', N'orphan_team_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.Team1CodeRaw), (r.Team2CodeRaw), (r.TossWinnerCodeRaw), (r.WinnerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.TeamsSnapshot AS m WHERE m.TeamCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.Team1CodeRaw), (r.Team2CodeRaw), (r.TossWinnerCodeRaw), (r.WinnerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.TeamsSnapshot AS m WHERE m.TeamCode = v.c))', N'DQ05', N'Team code not in the Teams master', 0, NULL, N'Reference data gap', N'Correct the team code in the file, or add the team to CricketSource.Teams and request reprocessing.'),
        (N'Match', N'orphan_venue_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.VenueCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.VenuesSnapshot AS m WHERE m.VenueCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.VenueCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.VenuesSnapshot AS m WHERE m.VenueCode = v.c))', NULL, N'Venue code not in the Venues master', 0, NULL, N'Reference data gap', N'Correct the venue code in the file, or add the venue to CricketSource.Venues and request reprocessing.'),
        (N'Match', N'orphan_player_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.ManOfMatchCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.ManOfMatchCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', NULL, N'Man of the match not in the Players master', 0, NULL, N'Reference data gap', N'Correct the player code in the file, or add the player to CricketSource.Players and request reprocessing.'),
        (N'Match', N'invalid_domain_value', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.ResultMethodRaw), '''') IS NOT NULL AND r.ResultMethodRaw NOT IN (''Normal'',''Tied'',''NoResult'',''Abandoned'',''SuperOver'')) OR (NULLIF(LTRIM(r.TossDecisionRaw), '''') IS NOT NULL AND r.TossDecisionRaw NOT IN (''Bat'',''Field''))', N'CONCAT(''result_method='', r.ResultMethodRaw, '' toss_decision='', r.TossDecisionRaw)', NULL, N'result_method / toss_decision outside the allowed list', 0, NULL, N'Source data entry', N'Use one of the allowed values and re-send the file.'),
        (N'Match', N'winner_not_participant', N'Consistency', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.WinnerCodeRaw), '''') IS NOT NULL AND r.WinnerCodeRaw NOT IN (ISNULL(r.Team1CodeRaw, ''''), ISNULL(r.Team2CodeRaw, ''''))', N'r.WinnerCodeRaw', NULL, N'Winner is neither Team1 nor Team2', 0, NULL, N'Source data entry', N'Correct the winner or team codes and re-send the file.'),
        (N'Match', N'invalid_numeric', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.WinMarginRaw), '''') IS NOT NULL AND (TRY_CAST(r.WinMarginRaw AS INT) IS NULL OR TRY_CAST(r.WinMarginRaw AS INT) < 0))', N'CONCAT_WS('' '', IIF((NULLIF(LTRIM(r.WinMarginRaw), '''') IS NOT NULL AND (TRY_CAST(r.WinMarginRaw AS INT) IS NULL OR TRY_CAST(r.WinMarginRaw AS INT) < 0)), CONCAT(''WinMarginRaw='', r.WinMarginRaw), NULL), NULL)', NULL, N'win_margin is not a non-negative integer', 0, NULL, N'Source data entry', N'Correct the value to a whole number and re-send the file.'),
        (N'Match', N'duplicate_file', N'Uniqueness', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM stg.MatchRaw AS r2 WHERE r2.SourceFileHash = r.SourceFileHash AND r2.SourceFileName COLLATE Latin1_General_BIN < r.SourceFileName COLLATE Latin1_General_BIN AND NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = r2.SourceFileHash))', N'CONCAT(''same content as '', (SELECT MIN(r2.SourceFileName COLLATE Latin1_General_BIN) FROM stg.MatchRaw AS r2 WHERE r2.SourceFileHash = r.SourceFileHash))', N'DQ08', N'Identical file content arrived earlier in this batch under another name', 0, NULL, N'File delivery / format', N'Nothing to load - the first copy was accepted. Stop re-sending the same content under a new name.'),
        (N'Innings', N'missing_required_field', N'Completeness', N'Rejected', N'SQL', N'r.InningsNo IS NULL OR NULLIF(LTRIM(r.MatchIdRaw), '''') IS NULL OR NULLIF(LTRIM(r.BattingTeamCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.BowlingTeamCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NULL OR NULLIF(LTRIM(r.WicketsLostRaw), '''') IS NULL OR NULLIF(LTRIM(r.OversPlayedRaw), '''') IS NULL', N'CONCAT(''missing:'', IIF(NULLIF(LTRIM(r.MatchIdRaw), '''') IS NULL, '' MatchIdRaw'', ''''), IIF(NULLIF(LTRIM(r.BattingTeamCodeRaw), '''') IS NULL, '' BattingTeamCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.BowlingTeamCodeRaw), '''') IS NULL, '' BowlingTeamCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NULL, '' RunsScoredRaw'', ''''), IIF(NULLIF(LTRIM(r.WicketsLostRaw), '''') IS NULL, '' WicketsLostRaw'', ''''), IIF(NULLIF(LTRIM(r.OversPlayedRaw), '''') IS NULL, '' OversPlayedRaw'', ''''))', N'DQ03', N'Required innings field is empty', 1, NULL, N'Source data entry', N'Populate the missing fields and re-send the file.'),
        (N'Innings', N'invalid_numeric', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NOT NULL AND TRY_CAST(r.RunsScoredRaw AS INT) IS NULL) OR (NULLIF(LTRIM(r.WicketsLostRaw), '''') IS NOT NULL AND TRY_CAST(r.WicketsLostRaw AS INT) IS NULL) OR (NULLIF(LTRIM(r.ExtrasTotalRaw), '''') IS NOT NULL AND TRY_CAST(r.ExtrasTotalRaw AS INT) IS NULL)', N'CONCAT_WS('' '', IIF((NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NOT NULL AND TRY_CAST(r.RunsScoredRaw AS INT) IS NULL), CONCAT(''RunsScoredRaw='', r.RunsScoredRaw), NULL), IIF((NULLIF(LTRIM(r.WicketsLostRaw), '''') IS NOT NULL AND TRY_CAST(r.WicketsLostRaw AS INT) IS NULL), CONCAT(''WicketsLostRaw='', r.WicketsLostRaw), NULL), IIF((NULLIF(LTRIM(r.ExtrasTotalRaw), '''') IS NOT NULL AND TRY_CAST(r.ExtrasTotalRaw AS INT) IS NULL), CONCAT(''ExtrasTotalRaw='', r.ExtrasTotalRaw), NULL), NULL)', NULL, N'Runs / wickets / extras not an integer', 1, NULL, N'Source data entry', N'Correct the value to a whole number and re-send the file.'),
        (N'Innings', N'negative_runs', N'Validity', N'Rejected', N'SQL', N'TRY_CAST(r.RunsScoredRaw AS INT) < 0 OR TRY_CAST(r.ExtrasTotalRaw AS INT) < 0', N'CONCAT_WS('' '', IIF(TRY_CAST(r.RunsScoredRaw AS INT) < 0, CONCAT(''RunsScoredRaw='', r.RunsScoredRaw), NULL), IIF(TRY_CAST(r.ExtrasTotalRaw AS INT) < 0, CONCAT(''ExtrasTotalRaw='', r.ExtrasTotalRaw), NULL), NULL)', NULL, N'Runs or extras below zero', 1, NULL, N'Source data entry', N'Correct the negative value and re-send the file.'),
        (N'Innings', N'wickets_exceed_ten', N'Validity', N'Rejected', N'SQL', N'TRY_CAST(r.WicketsLostRaw AS INT) > (SELECT CAST(ParameterValue AS INT) FROM config.Parameter WHERE ParameterName = ''MaxWicketsPerInnings'')', N'CONCAT(''wickets='', r.WicketsLostRaw)', N'DQ04', N'Wickets above config.Parameter MaxWicketsPerInnings', 1, NULL, N'Source data entry', N'Correct the wicket count (limit in config.Parameter) and re-send the file.'),
        (N'Innings', N'invalid_overs', N'Validity', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.OversPlayedRaw), '''') IS NOT NULL AND r.OversPlayedRaw NOT LIKE ''[0-9]'' AND r.OversPlayedRaw NOT LIKE ''[0-9][0-9]'' AND r.OversPlayedRaw NOT LIKE ''[0-9].[0-5]'' AND r.OversPlayedRaw NOT LIKE ''[0-9][0-9].[0-5]''', N'r.OversPlayedRaw', NULL, N'Overs not in o or o.b form with b 0-5', 1, NULL, N'Source data entry', N'Correct overs to o or o.b (b = 0-5) and re-send the file.'),
        (N'Innings', N'orphan_team_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.BattingTeamCodeRaw), (r.BowlingTeamCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.TeamsSnapshot AS m WHERE m.TeamCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.BattingTeamCodeRaw), (r.BowlingTeamCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.TeamsSnapshot AS m WHERE m.TeamCode = v.c))', NULL, N'Team code not in the Teams master', 1, NULL, N'Reference data gap', N'Correct the team code in the file, or add the team to CricketSource.Teams and request reprocessing.'),
        (N'Innings', N'parent_match_rejected', N'Integrity', N'Rejected', N'Workflow', NULL, NULL, NULL, N'Innings belongs to a match file rejected in this run (evaluated by 04 - depends on this run''s match results)', 0, NULL, N'Upstream dependency', N'Clears when the match file''s own issues are fixed.'),
        (N'Delivery', N'missing_required_field', N'Completeness', N'Rejected', N'SQL', N'r.InningsNo IS NULL OR r.OverNo IS NULL OR r.BallNo IS NULL OR NULLIF(LTRIM(r.MatchIdRaw), '''') IS NULL OR NULLIF(LTRIM(r.BatsmanCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.BowlerCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.RunsOffBatRaw), '''') IS NULL OR NULLIF(LTRIM(r.ExtraRunsRaw), '''') IS NULL OR NULLIF(LTRIM(r.WicketFlagRaw), '''') IS NULL', N'CONCAT(''missing:'', IIF(NULLIF(LTRIM(r.MatchIdRaw), '''') IS NULL, '' MatchIdRaw'', ''''), IIF(NULLIF(LTRIM(r.BatsmanCodeRaw), '''') IS NULL, '' BatsmanCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.BowlerCodeRaw), '''') IS NULL, '' BowlerCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.RunsOffBatRaw), '''') IS NULL, '' RunsOffBatRaw'', ''''), IIF(NULLIF(LTRIM(r.ExtraRunsRaw), '''') IS NULL, '' ExtraRunsRaw'', ''''), IIF(NULLIF(LTRIM(r.WicketFlagRaw), '''') IS NULL, '' WicketFlagRaw'', ''''))', NULL, N'Required delivery field is empty', 1, NULL, N'Source data entry', N'Populate the missing fields and re-send the file.'),
        (N'Delivery', N'invalid_numeric', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.RunsOffBatRaw), '''') IS NOT NULL AND TRY_CAST(r.RunsOffBatRaw AS INT) IS NULL) OR (NULLIF(LTRIM(r.ExtraRunsRaw), '''') IS NOT NULL AND TRY_CAST(r.ExtraRunsRaw AS INT) IS NULL)', N'CONCAT_WS('' '', IIF((NULLIF(LTRIM(r.RunsOffBatRaw), '''') IS NOT NULL AND TRY_CAST(r.RunsOffBatRaw AS INT) IS NULL), CONCAT(''RunsOffBatRaw='', r.RunsOffBatRaw), NULL), IIF((NULLIF(LTRIM(r.ExtraRunsRaw), '''') IS NOT NULL AND TRY_CAST(r.ExtraRunsRaw AS INT) IS NULL), CONCAT(''ExtraRunsRaw='', r.ExtraRunsRaw), NULL), NULL)', NULL, N'Runs not an integer', 1, NULL, N'Source data entry', N'Correct the value to a whole number and re-send the file.'),
        (N'Delivery', N'negative_runs', N'Validity', N'Rejected', N'SQL', N'TRY_CAST(r.RunsOffBatRaw AS INT) < 0 OR TRY_CAST(r.ExtraRunsRaw AS INT) < 0', N'CONCAT_WS('' '', IIF(TRY_CAST(r.RunsOffBatRaw AS INT) < 0, CONCAT(''RunsOffBatRaw='', r.RunsOffBatRaw), NULL), IIF(TRY_CAST(r.ExtraRunsRaw AS INT) < 0, CONCAT(''ExtraRunsRaw='', r.ExtraRunsRaw), NULL), NULL)', N'DQ06', N'Runs off bat or extras below zero', 1, NULL, N'Source data entry', N'Correct the negative value and re-send the file.'),
        (N'Delivery', N'orphan_player_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.BatsmanCodeRaw), (r.BowlerCodeRaw), (r.DismissedPlayerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.BatsmanCodeRaw), (r.BowlerCodeRaw), (r.DismissedPlayerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', N'DQ07', N'Player code not in the Players master', 1, NULL, N'Reference data gap', N'Correct the player code in the file, or add the player to CricketSource.Players and request reprocessing.'),
        (N'Delivery', N'invalid_domain_value', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.WicketFlagRaw), '''') IS NOT NULL AND r.WicketFlagRaw NOT IN (''Y'',''N'')) OR (NULLIF(LTRIM(r.ExtraTypeRaw), '''') IS NOT NULL AND r.ExtraTypeRaw NOT IN (''Wide'',''NoBall'',''Bye'',''LegBye'')) OR (NULLIF(LTRIM(r.DismissalTypeRaw), '''') IS NOT NULL AND r.DismissalTypeRaw NOT IN (''Bowled'',''LBW'',''Caught'',''RunOut'',''Stumped'',''HitWicket''))', N'CONCAT_WS('' '', CONCAT(''is_wicket='', r.WicketFlagRaw), CONCAT(''extra_type='', r.ExtraTypeRaw), CONCAT(''dismissal_type='', r.DismissalTypeRaw))', NULL, N'is_wicket / extra_type / dismissal_type outside the allowed list', 1, NULL, N'Source data entry', N'Use one of the allowed values and re-send the file.'),
        (N'Delivery', N'duplicate_natural_key', N'Uniqueness', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM stg.BallByBallRaw AS r2 WHERE r2.MatchIdRaw = r.MatchIdRaw AND r2.InningsNo = r.InningsNo AND r2.OverNo = r.OverNo AND r2.BallNo = r.BallNo AND r2.StgRowId <> r.StgRowId)', N'CONCAT((SELECT COUNT(*) FROM stg.BallByBallRaw AS r2 WHERE r2.MatchIdRaw = r.MatchIdRaw AND r2.InningsNo = r.InningsNo AND r2.OverNo = r.OverNo AND r2.BallNo = r.BallNo), '' rows'')', NULL, N'match|innings|over|ball appears more than once in staging', 1, NULL, N'File delivery / format', N'Remove the duplicate rows and re-send the file.'),
        (N'Delivery', N'batsman_dismissed_twice', N'Consistency', N'Flagged', N'SQL', N'r.WicketFlagRaw = ''Y'' AND EXISTS (SELECT 1 FROM stg.BallByBallRaw AS r2 WHERE r2.MatchIdRaw = r.MatchIdRaw AND r2.InningsNo = r.InningsNo AND r2.WicketFlagRaw = ''Y'' AND r2.DismissedPlayerCodeRaw = r.DismissedPlayerCodeRaw AND r2.StgRowId <> r.StgRowId)', N'CONCAT(r.DismissedPlayerCodeRaw, '' dismissed '', (SELECT COUNT(*) FROM stg.BallByBallRaw AS r2 WHERE r2.MatchIdRaw = r.MatchIdRaw AND r2.InningsNo = r.InningsNo AND r2.WicketFlagRaw = ''Y'' AND r2.DismissedPlayerCodeRaw = r.DismissedPlayerCodeRaw), '' times in this innings'')', NULL, N'The same batsman is dismissed more than once in an innings (found by warehouse reconciliation, not planted)', 0, NULL, N'Source data entry', N'Correct the dismissal records for this innings and re-send the deliveries file.'),
        (N'Delivery', N'orphan_match_reference', N'Integrity', N'Rejected', N'Workflow', NULL, NULL, NULL, N'Delivery''s match has no accepted header in this run or a previous run (evaluated by 04)', 0, NULL, N'Upstream dependency', N'Clears when the match header is accepted.'),
        (N'PlayerRanking', N'missing_required_field', N'Completeness', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.PlayerCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.FormatCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.DisciplineRaw), '''') IS NULL OR NULLIF(LTRIM(r.RankingDateRaw), '''') IS NULL OR NULLIF(LTRIM(r.RankPositionRaw), '''') IS NULL OR NULLIF(LTRIM(r.RatingPointsRaw), '''') IS NULL', N'CONCAT(''missing:'', IIF(NULLIF(LTRIM(r.PlayerCodeRaw), '''') IS NULL, '' PlayerCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.FormatCodeRaw), '''') IS NULL, '' FormatCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.DisciplineRaw), '''') IS NULL, '' DisciplineRaw'', ''''), IIF(NULLIF(LTRIM(r.RankingDateRaw), '''') IS NULL, '' RankingDateRaw'', ''''), IIF(NULLIF(LTRIM(r.RankPositionRaw), '''') IS NULL, '' RankPositionRaw'', ''''), IIF(NULLIF(LTRIM(r.RatingPointsRaw), '''') IS NULL, '' RatingPointsRaw'', ''''))', NULL, N'Required ranking field is empty', 0, NULL, N'Source data entry', N'Populate the missing fields and re-send the file.'),
        (N'PlayerRanking', N'invalid_date', N'Validity', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.RankingDateRaw), '''') IS NOT NULL AND TRY_CONVERT(date, r.RankingDateRaw, 103) IS NULL', N'r.RankingDateRaw', N'DQ10', N'ranking_date is not dd/mm/yyyy (the documented format - parsed, not an error)', 0, NULL, N'Source data entry', N'Correct the date to its documented format and re-send the file.'),
        (N'PlayerRanking', N'invalid_numeric', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.RankPositionRaw), '''') IS NOT NULL AND (TRY_CAST(r.RankPositionRaw AS INT) IS NULL OR TRY_CAST(r.RankPositionRaw AS INT) < 0)) OR (NULLIF(LTRIM(r.RatingPointsRaw), '''') IS NOT NULL AND (TRY_CAST(r.RatingPointsRaw AS INT) IS NULL OR TRY_CAST(r.RatingPointsRaw AS INT) < 0))', N'CONCAT_WS('' '', IIF((NULLIF(LTRIM(r.RankPositionRaw), '''') IS NOT NULL AND (TRY_CAST(r.RankPositionRaw AS INT) IS NULL OR TRY_CAST(r.RankPositionRaw AS INT) < 0)), CONCAT(''RankPositionRaw='', r.RankPositionRaw), NULL), IIF((NULLIF(LTRIM(r.RatingPointsRaw), '''') IS NOT NULL AND (TRY_CAST(r.RatingPointsRaw AS INT) IS NULL OR TRY_CAST(r.RatingPointsRaw AS INT) < 0)), CONCAT(''RatingPointsRaw='', r.RatingPointsRaw), NULL), NULL)', NULL, N'Rank / rating not a non-negative integer', 0, NULL, N'Source data entry', N'Correct the value to a whole number and re-send the file.'),
        (N'PlayerRanking', N'orphan_player_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.PlayerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.PlayerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', NULL, N'Player code not in the Players master', 0, NULL, N'Reference data gap', N'Correct the player code in the file, or add the player to CricketSource.Players and request reprocessing.'),
        (N'PlayerRanking', N'invalid_domain_value', N'Validity', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.DisciplineRaw), '''') IS NOT NULL AND r.DisciplineRaw NOT IN (''Batting'',''Bowling'',''AllRounder'')', N'CONCAT(''discipline='', r.DisciplineRaw)', NULL, N'discipline outside the allowed list', 0, NULL, N'Source data entry', N'Use one of the allowed values and re-send the file.'),
        (N'PlayerRanking', N'duplicate_natural_key', N'Uniqueness', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM stg.PlayerRankingRaw AS r2 WHERE r2.PlayerCodeRaw = r.PlayerCodeRaw AND r2.FormatCodeRaw = r.FormatCodeRaw AND r2.DisciplineRaw = r.DisciplineRaw AND r2.RankingDateRaw = r.RankingDateRaw AND r2.StgRowId <> r.StgRowId)', N'CONCAT((SELECT COUNT(*) FROM stg.PlayerRankingRaw AS r2 WHERE r2.PlayerCodeRaw = r.PlayerCodeRaw AND r2.FormatCodeRaw = r.FormatCodeRaw AND r2.DisciplineRaw = r.DisciplineRaw AND r2.RankingDateRaw = r.RankingDateRaw), '' rows'')', NULL, N'player|format|discipline|date appears more than once', 0, NULL, N'File delivery / format', N'Remove the duplicate rows and re-send the file.'),
        (N'HistoricalStats', N'missing_required_field', N'Completeness', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.PlayerCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.SeasonRaw), '''') IS NULL OR NULLIF(LTRIM(r.FormatCodeRaw), '''') IS NULL OR NULLIF(LTRIM(r.MatchesPlayedRaw), '''') IS NULL OR NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NULL OR NULLIF(LTRIM(r.WicketsTakenRaw), '''') IS NULL', N'CONCAT(''missing:'', IIF(NULLIF(LTRIM(r.PlayerCodeRaw), '''') IS NULL, '' PlayerCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.SeasonRaw), '''') IS NULL, '' SeasonRaw'', ''''), IIF(NULLIF(LTRIM(r.FormatCodeRaw), '''') IS NULL, '' FormatCodeRaw'', ''''), IIF(NULLIF(LTRIM(r.MatchesPlayedRaw), '''') IS NULL, '' MatchesPlayedRaw'', ''''), IIF(NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NULL, '' RunsScoredRaw'', ''''), IIF(NULLIF(LTRIM(r.WicketsTakenRaw), '''') IS NULL, '' WicketsTakenRaw'', ''''))', NULL, N'Required stats field is empty', 0, NULL, N'Source data entry', N'Populate the missing fields and re-send the file.'),
        (N'HistoricalStats', N'invalid_numeric', N'Validity', N'Rejected', N'SQL', N'(NULLIF(LTRIM(r.MatchesPlayedRaw), '''') IS NOT NULL AND TRY_CAST(r.MatchesPlayedRaw AS INT) IS NULL) OR (NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NOT NULL AND TRY_CAST(r.RunsScoredRaw AS INT) IS NULL) OR (NULLIF(LTRIM(r.WicketsTakenRaw), '''') IS NOT NULL AND TRY_CAST(r.WicketsTakenRaw AS INT) IS NULL)', N'CONCAT_WS('' '', IIF((NULLIF(LTRIM(r.MatchesPlayedRaw), '''') IS NOT NULL AND TRY_CAST(r.MatchesPlayedRaw AS INT) IS NULL), CONCAT(''MatchesPlayedRaw='', r.MatchesPlayedRaw), NULL), IIF((NULLIF(LTRIM(r.RunsScoredRaw), '''') IS NOT NULL AND TRY_CAST(r.RunsScoredRaw AS INT) IS NULL), CONCAT(''RunsScoredRaw='', r.RunsScoredRaw), NULL), IIF((NULLIF(LTRIM(r.WicketsTakenRaw), '''') IS NOT NULL AND TRY_CAST(r.WicketsTakenRaw AS INT) IS NULL), CONCAT(''WicketsTakenRaw='', r.WicketsTakenRaw), NULL), NULL)', NULL, N'Counts not an integer', 0, NULL, N'Source data entry', N'Correct the value to a whole number and re-send the file.'),
        (N'HistoricalStats', N'negative_runs', N'Validity', N'Rejected', N'SQL', N'TRY_CAST(r.MatchesPlayedRaw AS INT) < 0 OR TRY_CAST(r.RunsScoredRaw AS INT) < 0 OR TRY_CAST(r.WicketsTakenRaw AS INT) < 0', N'CONCAT_WS('' '', IIF(TRY_CAST(r.MatchesPlayedRaw AS INT) < 0, CONCAT(''MatchesPlayedRaw='', r.MatchesPlayedRaw), NULL), IIF(TRY_CAST(r.RunsScoredRaw AS INT) < 0, CONCAT(''RunsScoredRaw='', r.RunsScoredRaw), NULL), IIF(TRY_CAST(r.WicketsTakenRaw AS INT) < 0, CONCAT(''WicketsTakenRaw='', r.WicketsTakenRaw), NULL), NULL)', NULL, N'Counts below zero', 0, NULL, N'Source data entry', N'Correct the negative value and re-send the file.'),
        (N'HistoricalStats', N'orphan_player_reference', N'Integrity', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM (VALUES (r.PlayerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', N'(SELECT STRING_AGG(v.c, '' '') FROM (VALUES (r.PlayerCodeRaw)) AS v(c) WHERE NULLIF(LTRIM(v.c), '''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stg.PlayersSnapshot AS m WHERE m.PlayerCode = v.c))', N'DQ07', N'Player code not in the Players master', 0, NULL, N'Reference data gap', N'Correct the player code in the file, or add the player to CricketSource.Players and request reprocessing.'),
        (N'HistoricalStats', N'duplicate_natural_key', N'Uniqueness', N'Rejected', N'SQL', N'EXISTS (SELECT 1 FROM stg.HistoricalStatsRaw AS r2 WHERE r2.PlayerCodeRaw = r.PlayerCodeRaw AND r2.SeasonRaw = r.SeasonRaw AND r2.FormatCodeRaw = r.FormatCodeRaw AND r2.StgRowId <> r.StgRowId)', N'CONCAT((SELECT COUNT(*) FROM stg.HistoricalStatsRaw AS r2 WHERE r2.PlayerCodeRaw = r.PlayerCodeRaw AND r2.SeasonRaw = r.SeasonRaw AND r2.FormatCodeRaw = r.FormatCodeRaw), '' rows'')', NULL, N'player|season|format appears more than once', 0, NULL, N'File delivery / format', N'Remove the duplicate rows and re-send the file.'),
        (N'Player', N'missing_required_field', N'Completeness', N'Rejected', N'SQL', N'NULLIF(LTRIM(r.PlayerCode), '''') IS NULL OR NULLIF(LTRIM(r.FullName), '''') IS NULL', N'CONCAT(''missing:'', IIF(NULLIF(LTRIM(r.PlayerCode), '''') IS NULL, '' PlayerCode'', ''''), IIF(NULLIF(LTRIM(r.FullName), '''') IS NULL, '' FullName'', ''''))', NULL, N'Player code or name is empty', 0, NULL, N'Source data entry', N'Populate the missing fields and re-send the file.'),
        (N'Player', N'missing_date_of_birth', N'Completeness', N'Flagged', N'SQL', N'r.DateOfBirth IS NULL', N'''NULL''', N'DQ01', N'No date of birth; loads as NULL', 0, NULL, N'Incomplete master data', N'Add the date of birth in CricketSource.Players.'),
        (N'Player', N'future_date_of_birth', N'Validity', N'Defaulted', N'SQL', N'r.DateOfBirth > CAST(GETDATE() AS date)', N'CONVERT(VARCHAR(10), r.DateOfBirth, 23)', N'DQ02', N'Date of birth in the future; workflow 04 loads it as NULL so the player and his facts still load', 0, NULL, N'Source data entry', N'Correct the date of birth in CricketSource.Players.'),
        (N'File', N'schema_mismatch', N'Conformity', N'Rejected', N'Workflow', NULL, NULL, N'DQ13', N'CSV header matches no config.DQEntity.ExpectedHeader (evaluated by 04 - reads the file itself)', 0, NULL, N'File delivery / format', N'Re-send the file with the documented header and column count (CSV_SCHEMA.md).'),
        (N'Innings', N'innings_runs_mismatch', N'Consistency', N'Flagged', N'SQL', N'TRY_CAST(r.RunsScoredRaw AS INT) <> (SELECT SUM(TRY_CAST(b.RunsOffBatRaw AS INT) + TRY_CAST(b.ExtraRunsRaw AS INT)) FROM stg.BallByBallRaw AS b WHERE b.MatchIdRaw = r.MatchIdRaw AND b.InningsNo = r.InningsNo + 1)', N'CONCAT(''scorecard='', r.RunsScoredRaw, '' ballbyball='', (SELECT SUM(TRY_CAST(b.RunsOffBatRaw AS INT) + TRY_CAST(b.ExtraRunsRaw AS INT)) FROM stg.BallByBallRaw AS b WHERE b.MatchIdRaw = r.MatchIdRaw AND b.InningsNo = r.InningsNo + 1))', NULL, N'Innings runs in the JSON scorecard differ from the sum of its deliveries (only checked when deliveries exist)', 1, N'NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = r.SourceFileHash) OR EXISTS (SELECT 1 FROM stg.BallByBallRaw AS b WHERE b.MatchIdRaw = r.MatchIdRaw AND NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = b.SourceFileHash))', N'Cross-source disagreement', N'Reconcile the scorecard with the ball-by-ball feed and re-send whichever source is wrong.'),
        (N'Innings', N'innings_wickets_mismatch', N'Consistency', N'Flagged', N'SQL', N'TRY_CAST(r.WicketsLostRaw AS INT) <> (SELECT SUM(IIF(b.WicketFlagRaw = ''Y'', 1, 0)) FROM stg.BallByBallRaw AS b WHERE b.MatchIdRaw = r.MatchIdRaw AND b.InningsNo = r.InningsNo + 1)', N'CONCAT(''scorecard='', r.WicketsLostRaw, '' ballbyball='', (SELECT SUM(IIF(b.WicketFlagRaw = ''Y'', 1, 0)) FROM stg.BallByBallRaw AS b WHERE b.MatchIdRaw = r.MatchIdRaw AND b.InningsNo = r.InningsNo + 1))', NULL, N'Innings wickets in the JSON scorecard differ from the wickets in its deliveries (only checked when deliveries exist)', 1, N'NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = r.SourceFileHash) OR EXISTS (SELECT 1 FROM stg.BallByBallRaw AS b WHERE b.MatchIdRaw = r.MatchIdRaw AND NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = b.SourceFileHash))', N'Cross-source disagreement', N'Reconcile the scorecard with the ball-by-ball feed and re-send whichever source is wrong.'),
        (N'Delivery', N'match_ballbyball_held', N'Completeness', N'Rejected', N'Workflow', NULL, NULL, NULL, N'Held back because another delivery of the same match failed, or the match totals disagree with its deliveries (evaluated by 04 - the match is the unit of acceptance for ball-by-ball)', 0, NULL, N'Upstream dependency', N'Clears when the match''s failing deliveries or totals are corrected and re-sent.')
    ) AS s (EntityType, RuleCode, Dimension, ActionTaken, EvaluatedBy, RulePredicate, RawValueExpr, PlantedIssue, Description,
            HoldsBallByBall, ScopePredicate, RootCauseCategory, RemediationHint)
ON t.EntityType = s.EntityType AND t.RuleCode = s.RuleCode
WHEN MATCHED THEN UPDATE SET Dimension = s.Dimension, ActionTaken = s.ActionTaken, EvaluatedBy = s.EvaluatedBy,
    RulePredicate = s.RulePredicate, RawValueExpr = s.RawValueExpr, PlantedIssue = s.PlantedIssue, Description = s.Description,
    HoldsBallByBall = s.HoldsBallByBall, ScopePredicate = s.ScopePredicate, RootCauseCategory = s.RootCauseCategory,
    RemediationHint = s.RemediationHint
WHEN NOT MATCHED THEN INSERT (EntityType, RuleCode, Dimension, ActionTaken, EvaluatedBy, RulePredicate, RawValueExpr, PlantedIssue, Description,
                              HoldsBallByBall, ScopePredicate, RootCauseCategory, RemediationHint)
    VALUES (s.EntityType, s.RuleCode, s.Dimension, s.ActionTaken, s.EvaluatedBy, s.RulePredicate, s.RawValueExpr, s.PlantedIssue, s.Description,
            s.HoldsBallByBall, s.ScopePredicate, s.RootCauseCategory, s.RemediationHint);
GO

-- One runnable statement per active SQL rule, all returning the same five columns.
CREATE OR ALTER VIEW config.vw_DQRuleSql AS
SELECT
    d.RuleId,
    d.EntityType,
    d.RuleCode,
    CAST(CONCAT(
        N'SELECT ', d.RuleId, N' AS RuleId, CAST(r.StgRowId AS BIGINT) AS StgRowId, ',
        N'CAST(', e.NaturalKeyExpr, N' AS VARCHAR(100)) AS NaturalKey, ',
        N'CAST(', e.SourceFileExpr, N' AS VARCHAR(260)) AS SourceFile, ',
        N'CAST(LEFT(CONVERT(VARCHAR(400), ', d.RawValueExpr, N'), 200) AS VARCHAR(200)) AS RawValue ',
        N'FROM ', e.StagingTable, N' AS r WHERE (', d.RulePredicate, N')',
        CASE WHEN d.ScopePredicate IS NOT NULL THEN CONCAT(N' AND (', d.ScopePredicate, N')')
             WHEN e.IsFileBased = 1
             THEN N' AND NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = r.SourceFileHash)'
             ELSE N'' END
    ) AS NVARCHAR(MAX)) AS RuleSql
FROM config.DQRule AS d
JOIN config.DQEntity AS e ON e.EntityType = d.EntityType
WHERE d.IsActive = 1 AND d.EvaluatedBy = 'SQL';
GO

-- Every staged file with its row count. RowsRead for a JSON file = header row + innings rows.
CREATE OR ALTER VIEW stg.vw_DQStagedFile AS
SELECT SourceFileName, SourceFileHash, SourceType, SUM(n) AS RowsRead
FROM (
    SELECT SourceFileName, SourceFileHash, 'JSON' AS SourceType, COUNT(*) AS n FROM stg.MatchRaw GROUP BY SourceFileName, SourceFileHash
    UNION ALL SELECT SourceFileName, SourceFileHash, 'JSON', COUNT(*) FROM stg.InningsRaw GROUP BY SourceFileName, SourceFileHash
    UNION ALL SELECT SourceFileName, SourceFileHash, 'CSV', COUNT(*) FROM stg.BallByBallRaw GROUP BY SourceFileName, SourceFileHash
    UNION ALL SELECT SourceFileName, SourceFileHash, 'CSV', COUNT(*) FROM stg.PlayerRankingRaw GROUP BY SourceFileName, SourceFileHash
    UNION ALL SELECT SourceFileName, SourceFileHash, 'CSV', COUNT(*) FROM stg.HistoricalStatsRaw GROUP BY SourceFileName, SourceFileHash
) AS x
GROUP BY SourceFileName, SourceFileHash, SourceType;
GO

-- Files 04 validates this run: content hash never seen by Audit_FileControl.
-- Reprocessed = same file name was accepted before with different content (a corrected file).
CREATE OR ALTER VIEW stg.vw_DQPendingFile AS
SELECT s.SourceFileName, s.SourceFileHash, s.SourceType, s.RowsRead,
       CASE WHEN EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc
                         WHERE fc.FileName = s.SourceFileName AND fc.Status IN ('New','Reprocessed'))
            THEN 'Reprocessed' ELSE 'New' END AS FileStatus
FROM stg.vw_DQStagedFile AS s
WHERE NOT EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = s.SourceFileHash);
GO

-- Files skipped this run: identical content already validated in an earlier run.
CREATE OR ALTER VIEW stg.vw_DQSkippedFile AS
SELECT s.SourceFileName, s.SourceFileHash, s.SourceType
FROM stg.vw_DQStagedFile AS s
WHERE EXISTS (SELECT 1 FROM audit.Audit_FileControl AS fc WHERE fc.FileHash = s.SourceFileHash);
GO

-- Match ids accepted in an earlier run (their file was New/Reprocessed). Deliveries arriving now for
-- those matches are not orphans even though the match file itself is skipped this run.
CREATE OR ALTER VIEW stg.vw_DQPriorAcceptedMatch AS
SELECT DISTINCT m.MatchIdRaw AS MatchId
FROM stg.MatchRaw AS m
JOIN audit.Audit_FileControl AS fc
  ON fc.FileName = m.SourceFileName AND fc.FileHash = m.SourceFileHash AND fc.Status IN ('New','Reprocessed')
WHERE m.MatchIdRaw IS NOT NULL;
GO
