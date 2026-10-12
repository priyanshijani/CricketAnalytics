-- Referential integrity: the declared foreign keys, the relationships no constraint enforces (completeness,
-- bridge, reporting-view keys the Tableau pickers rely on) and audit lineage (every row traceable to its file,
-- rule and run). Valid after any successful run.
-- One row per check: Suite, CheckId, CheckName, Expected, Actual, Result. Test cases: RI-xx in
-- 06_Tests/test_cases/sql_quality_test_cases.md. Expected is the number of orphans allowed (0).
SET NOCOUNT ON;
USE CricketDW;

DECLARE @r TABLE (CheckId VARCHAR(10), CheckName NVARCHAR(200), Expected BIGINT, Actual BIGINT);

-- ---- Declared constraints
INSERT @r SELECT 'RI01', N'Foreign keys disabled or not trusted', 0,
    (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled = 1 OR is_not_trusted = 1);
DECLARE @v TABLE (TableName NVARCHAR(400), ConstraintName NVARCHAR(400), Condition NVARCHAR(MAX));
INSERT @v EXEC ('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS, NO_INFOMSGS');
INSERT @r SELECT 'RI02', N'Rows violating a foreign key or check constraint (DBCC CHECKCONSTRAINTS)', 0, (SELECT COUNT(*) FROM @v);

-- ---- Warehouse relationships no constraint enforces
INSERT @r SELECT 'RI03', N'Played matches without innings', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult AS fm
     WHERE fm.ResultMethod NOT IN ('Abandoned') AND ISNULL(fm.InningsStatus, '') = 'Complete'
       AND NOT EXISTS (SELECT 1 FROM dw.Fact_Innings AS i WHERE i.MatchKey = fm.MatchKey));
INSERT @r SELECT 'RI04', N'Innings of a loaded ball-by-ball match without deliveries', 0,
    (SELECT COUNT(*) FROM dw.Fact_Innings AS i JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = i.MatchKey
     WHERE fm.BallByBallStatus = 'Loaded'
       AND NOT EXISTS (SELECT 1 FROM dw.Fact_BallByBall AS b WHERE b.MatchKey = i.MatchKey AND b.InningsNo = i.InningsNo));
INSERT @r SELECT 'RI05', N'Batter-team-season in the facts but not in Bridge_PlayerTeamSeason', 0,
    (SELECT COUNT(*) FROM (SELECT DISTINCT b.PlayerKey, b.TeamKey, fm.Season
                           FROM dw.Fact_BattingPerformance AS b JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = b.MatchKey) AS x
     WHERE NOT EXISTS (SELECT 1 FROM dw.Bridge_PlayerTeamSeason AS br
                       WHERE br.PlayerKey = x.PlayerKey AND br.TeamKey = x.TeamKey AND br.Season = x.Season));

-- ---- Reporting-view keys (each Tableau data source is a separate extract joined only by these keys)
INSERT @r SELECT 'RI06', N'rpt rows whose MatchId is not in rpt.Match', 0,
    (SELECT COUNT(*) FROM rpt.TeamMatch WHERE MatchId NOT IN (SELECT MatchId FROM rpt.Match))
  + (SELECT COUNT(*) FROM rpt.BattingInnings WHERE MatchId NOT IN (SELECT MatchId FROM rpt.Match))
  + (SELECT COUNT(*) FROM rpt.BowlingInnings WHERE MatchId NOT IN (SELECT MatchId FROM rpt.Match))
  + (SELECT COUNT(*) FROM rpt.OverProgression WHERE MatchId NOT IN (SELECT MatchId FROM rpt.Match))
  + (SELECT COUNT(*) FROM rpt.FallOfWicket WHERE MatchId NOT IN (SELECT MatchId FROM rpt.Match))
  + (SELECT COUNT(*) FROM rpt.Partnership WHERE MatchId NOT IN (SELECT MatchId FROM rpt.Match));
INSERT @r SELECT 'RI07', N'rpt rows whose PlayerCode is not in rpt.Player', 0,
    (SELECT COUNT(*) FROM rpt.BattingInnings WHERE PlayerCode NOT IN (SELECT PlayerCode FROM rpt.Player))
  + (SELECT COUNT(*) FROM rpt.BowlingInnings WHERE PlayerCode NOT IN (SELECT PlayerCode FROM rpt.Player))
  + (SELECT COUNT(*) FROM rpt.PlayerSeason WHERE PlayerCode NOT IN (SELECT PlayerCode FROM rpt.Player))
  + (SELECT COUNT(*) FROM rpt.PlayerPhase WHERE PlayerCode NOT IN (SELECT PlayerCode FROM rpt.Player))
  + (SELECT COUNT(*) FROM rpt.PlayerRanking WHERE PlayerCode NOT IN (SELECT PlayerCode FROM rpt.Player));
INSERT @r SELECT 'RI08', N'Player on a player-dashboard chart missing from the player picker (rpt.PlayerCareer)', 0,
    (SELECT COUNT(DISTINCT PlayerName) FROM (SELECT PlayerName FROM rpt.BattingInnings UNION SELECT PlayerName FROM rpt.PlayerSeason
                                              UNION SELECT PlayerName FROM rpt.PlayerPhase) AS x
     WHERE PlayerName NOT IN (SELECT PlayerName FROM rpt.PlayerCareer));
INSERT @r SELECT 'RI09', N'Team on a team-dashboard chart missing from the team picker (rpt.TeamMatch)', 0,
    (SELECT COUNT(DISTINCT t) FROM (SELECT TeamCurrentName AS t FROM rpt.TeamSeason UNION SELECT BattingTeamCurrentName FROM rpt.Partnership) AS x
     WHERE t NOT IN (SELECT TeamCurrentName FROM rpt.TeamMatch));
INSERT @r SELECT 'RI10', N'Match picker labels not unique, or not starting with the MatchId', 0,
    (SELECT COUNT(*) - COUNT(DISTINCT MatchLabel) FROM rpt.Match)
  + (SELECT COUNT(*) FROM rpt.Match WHERE MatchLabel NOT LIKE MatchId + ' | %');

-- ---- Audit lineage
INSERT @r SELECT 'RI11', N'DQ exceptions whose rule is not in config.DQRule', 0,
    (SELECT COUNT(*) FROM audit.Audit_DQException WHERE RuleId IS NOT NULL AND RuleId NOT IN (SELECT RuleId FROM config.DQRule));
INSERT @r SELECT 'RI12', N'DQ exceptions not traceable to a received file or the master-data source', 0,
    (SELECT COUNT(*) FROM audit.Audit_DQException
     WHERE SourceFile NOT IN (SELECT FileName FROM audit.Audit_FileControl) AND SourceFile NOT LIKE 'CricketSource.%');
INSERT @r SELECT 'RI13', N'Warehouse matches whose source file is not in Audit_FileControl', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult WHERE SourceFileHash NOT IN (SELECT FileHash FROM audit.Audit_FileControl));
INSERT @r SELECT 'RI14', N'Run ids (file control, DQ scores, warehouse) with no entry in the run log', 0,
    (SELECT COUNT(DISTINCT LoadRunId) FROM audit.Audit_FileControl WHERE LoadRunId NOT IN (SELECT LoadRunId FROM audit.Audit_ETLRunLog))
  + (SELECT COUNT(DISTINCT LoadRunId) FROM audit.DQRunScore WHERE LoadRunId NOT IN (SELECT LoadRunId FROM audit.Audit_ETLRunLog))
  + (SELECT COUNT(DISTINCT LoadRunId) FROM dw.Fact_MatchResult WHERE LoadRunId NOT IN (SELECT LoadRunId FROM audit.Audit_ETLRunLog));
INSERT @r SELECT 'RI15', N'Rows left in the validated queue or load tables after a successful publish', 0,
    (SELECT COUNT(*) FROM stg.MatchValid) + (SELECT COUNT(*) FROM stg.InningsValid) + (SELECT COUNT(*) FROM stg.BallByBallValid)
  + (SELECT COUNT(*) FROM stg.MatchCompletenessValid) + (SELECT COUNT(*) FROM stg.LoadReady_Control)
  + (SELECT COUNT(*) FROM stg.LoadReady_BallByBall) + (SELECT COUNT(*) FROM stg.LoadReady_Match);

SELECT 'Referential integrity' AS Suite, CheckId, CheckName, Expected, Actual,
       CASE WHEN Expected = Actual THEN 'PASS' ELSE 'FAIL' END AS Result
FROM @r ORDER BY CheckId;
