-- Business-rule assertions on the warehouse and the rpt layer: cricket's own rules (what any scorecard must
-- satisfy) and the calculation rules in 07_Docs/business_rules.md. Valid after any successful run.
-- One row per check: Suite, CheckId, CheckName, Expected, Actual, Result. Test cases: BR-xx in
-- 06_Tests/test_cases/sql_quality_test_cases.md. Expected is the number of violations allowed (0).
SET NOCOUNT ON;
USE CricketDW;

DECLARE @r TABLE (CheckId VARCHAR(10), CheckName NVARCHAR(200), Expected BIGINT, Actual BIGINT);

-- ---- Cricket rules on the facts
INSERT @r SELECT 'BR01', N'Innings with more than 10 wickets', 0, (SELECT COUNT(*) FROM dw.Fact_Innings WHERE WicketsLost > 10);
INSERT @r SELECT 'BR02', N'Innings longer than 20 overs (T20)', 0, (SELECT COUNT(*) FROM dw.Fact_Innings WHERE OversPlayed > 20);
INSERT @r SELECT 'BR03', N'Overs with more than 6 legal balls', 0,
    (SELECT COUNT(*) FROM (SELECT MatchKey, InningsNo, OverNo FROM dw.Fact_BallByBall
                           WHERE ISNULL(ExtraType, '') NOT IN ('Wide', 'NoBall')
                           GROUP BY MatchKey, InningsNo, OverNo HAVING COUNT(*) > 6) AS x);
INSERT @r SELECT 'BR04', N'Negative runs (balls, batting, bowling, innings)', 0,
    (SELECT COUNT(*) FROM dw.Fact_BallByBall WHERE RunsOffBat < 0 OR ExtraRuns < 0)
  + (SELECT COUNT(*) FROM dw.Fact_BattingPerformance WHERE RunsScored < 0 OR BallsFaced < 0)
  + (SELECT COUNT(*) FROM dw.Fact_BowlingPerformance WHERE RunsConceded < 0 OR Wickets < 0)
  + (SELECT COUNT(*) FROM dw.Fact_Innings WHERE RunsScored < 0);
-- A known source defect (DQ rule batsman_dismissed_twice keeps the balls and flags them): the check is that
-- every such case IS flagged - an unflagged one means the DQ gate missed it.
INSERT @r SELECT 'BR05', N'Batter dismissed twice in an innings and not flagged by the DQ gate', 0,
    (SELECT COUNT(*) FROM (SELECT b.MatchKey, b.InningsNo, b.DismissedPlayerKey FROM dw.Fact_BallByBall AS b
                           WHERE b.IsWicket = 1 AND b.DismissedPlayerKey IS NOT NULL
                           GROUP BY b.MatchKey, b.InningsNo, b.DismissedPlayerKey HAVING COUNT(*) > 1) AS x
     JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = x.MatchKey
     WHERE NOT EXISTS (SELECT 1 FROM audit.Audit_DQException AS e
                       WHERE e.RuleViolated = 'batsman_dismissed_twice'
                         AND e.NaturalKey LIKE fm.MatchId + '|' + CAST(x.InningsNo AS VARCHAR(2)) + '|%'));
INSERT @r SELECT 'BR06', N'Bowler with more than 4 overs in an innings (T20 limit)', 0,
    (SELECT COUNT(*) FROM dw.Fact_BowlingPerformance WHERE OversBowled > 4);
INSERT @r SELECT 'BR07', N'Fall-of-wicket numbers not 1..n in order', 0,
    (SELECT COUNT(*) FROM (SELECT MatchKey, InningsNo FROM dw.Fact_FallOfWicket
                           GROUP BY MatchKey, InningsNo HAVING MIN(WicketNumber) <> 1 OR MAX(WicketNumber) <> COUNT(*)) AS x);

-- ---- Match results
INSERT @r SELECT 'BR08', N'Team playing itself', 0, (SELECT COUNT(*) FROM dw.Fact_MatchResult WHERE Team1Key = Team2Key);
INSERT @r SELECT 'BR09', N'Winner or toss winner not one of the two teams', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult AS fm
     JOIN dw.Dim_Team AS t1 ON t1.TeamKey = fm.Team1Key JOIN dw.Dim_Team AS t2 ON t2.TeamKey = fm.Team2Key
     LEFT JOIN dw.Dim_Team AS w ON w.TeamKey = fm.WinnerTeamKey LEFT JOIN dw.Dim_Team AS tw ON tw.TeamKey = fm.TossWinnerTeamKey
     WHERE (fm.WinnerTeamKey IS NOT NULL AND w.TeamCode NOT IN (t1.TeamCode, t2.TeamCode))
        OR (fm.TossWinnerTeamKey IS NOT NULL AND tw.TeamCode NOT IN (t1.TeamCode, t2.TeamCode)));
INSERT @r SELECT 'BR10', N'No-result / abandoned match with a winner, or a normal result without one', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult
     WHERE (ResultMethod IN ('NoResult', 'Abandoned') AND WinnerTeamKey IS NOT NULL)
        OR (ResultMethod = 'Normal' AND WinnerTeamKey IS NULL));
WITH m AS (SELECT fm.WinMarginType, fm.WinMargin, fm.WinnerTeamKey, i1.BattingTeamKey AS bat1, i1.RunsScored AS r1,
                  i2.BattingTeamKey AS bat2, i2.RunsScored AS r2, i2.WicketsLost AS w2
           FROM dw.Fact_MatchResult AS fm
           JOIN dw.Fact_Innings AS i1 ON i1.MatchKey = fm.MatchKey AND i1.InningsNo = 1
           JOIN dw.Fact_Innings AS i2 ON i2.MatchKey = fm.MatchKey AND i2.InningsNo = 2
           WHERE fm.ResultMethod = 'Normal')
INSERT @r SELECT 'BR11', N'Margin inconsistent with the scores (runs win by the side batting first, wickets win by the chaser)', 0,
    SUM(CASE WHEN (WinMarginType = 'Runs' AND (WinnerTeamKey <> bat1 OR WinMargin <> r1 - r2))
              OR (WinMarginType = 'Wickets' AND (WinnerTeamKey <> bat2 OR WinMargin <> 10 - w2 OR r2 <= r1)) THEN 1 ELSE 0 END)
FROM m;
WITH m AS (SELECT fm.WinnerTeamKey, i1.RunsScored AS r1, i2.BattingTeamKey AS bat2, i2.RunsScored AS r2
           FROM dw.Fact_MatchResult AS fm
           JOIN dw.Fact_Innings AS i1 ON i1.MatchKey = fm.MatchKey AND i1.InningsNo = 1
           JOIN dw.Fact_Innings AS i2 ON i2.MatchKey = fm.MatchKey AND i2.InningsNo = 2
           WHERE fm.ResultMethod = 'Normal')
INSERT @r SELECT 'BR12', N'Chase that continued after the target was passed (more than 6 runs over)', 0,
    SUM(CASE WHEN WinnerTeamKey = bat2 AND r2 > r1 + 6 THEN 1 ELSE 0 END) FROM m;
INSERT @r SELECT 'BR13', N'Season label differs from the year of the match date', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult AS fm JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
     WHERE CAST(fm.Season AS VARCHAR(10)) <> CAST(YEAR(d.FullDate) AS VARCHAR(10)));

-- ---- Calculation rules (07_Docs/business_rules.md), via the rpt functions and views
INSERT @r SELECT 'BR14', N'Strike rate with 0 balls faced is not NULL', 0,
    (SELECT COUNT(*) FROM rpt.BattingInnings WHERE BallsFaced = 0 AND StrikeRate IS NOT NULL)
  + CASE WHEN rpt.fn_StrikeRate(10, 0) IS NULL THEN 0 ELSE 1 END;
INSERT @r SELECT 'BR15', N'Batting average when never dismissed is not NULL', 0,
    CASE WHEN rpt.fn_BattingAverage(50, 0) IS NULL THEN 0 ELSE 1 END
  + (SELECT COUNT(*) FROM rpt.PlayerCareer WHERE Dismissals = 0 AND BattingAverage IS NOT NULL);
INSERT @r SELECT 'BR16', N'Overs notation wrong (23 balls <> 3.5 overs)', 0,
    CASE WHEN rpt.fn_BallsFromOvers(3.5) = 23 AND rpt.fn_OversFromBalls(23) = 3.5 THEN 0 ELSE 1 END;
INSERT @r SELECT 'BR17', N'Economy <> runs x 6 / legal balls', 0,
    (SELECT COUNT(*) FROM rpt.PlayerCareer
     WHERE ABS(Economy - RunsConceded * 6.0 / NULLIF(LegalBallsBowled, 0)) > 0.01);   -- NULLIF: SQL does not short-circuit AND
INSERT @r SELECT 'BR18', N'Win % outside 0-100, or team season W+L+T+NR <> played', 0,
    (SELECT COUNT(*) FROM rpt.TeamSeason WHERE WinPct NOT BETWEEN 0 AND 100 OR Won + Lost + Tied + NoResult <> Played);
INSERT @r SELECT 'BR19', N'Fifty / hundred flags inconsistent with runs', 0,
    (SELECT COUNT(*) FROM rpt.BattingInnings
     WHERE IsFifty <> CASE WHEN RunsScored BETWEEN 50 AND 99 THEN 1 ELSE 0 END
        OR IsHundred <> CASE WHEN RunsScored >= 100 THEN 1 ELSE 0 END);
INSERT @r SELECT 'BR20', N'Decided match without exactly one Won and one Lost team row', 0,
    (SELECT COUNT(*) FROM (SELECT MatchId FROM rpt.TeamMatch WHERE IsDecided = 1 AND Result IN ('Won', 'Lost')
                           GROUP BY MatchId HAVING SUM(IsWin) <> 1 OR COUNT(*) <> 2) AS x);
INSERT @r SELECT 'BR21', N'Running win % after the last match <> season win %', 0,
    (SELECT COUNT(*) FROM rpt.TeamMatch AS tm JOIN rpt.TeamSeason AS ts ON ts.TeamCode = tm.TeamCode AND ts.Season = tm.Season
     WHERE tm.SeasonMatchNo = ts.Played AND ABS(tm.RunningWinPct * 100 - ts.WinPct) > 0.01);
INSERT @r SELECT 'BR22', N'Held ball-by-ball data present in ball-level views', 0,
    (SELECT COUNT(*) FROM rpt.BattingInnings AS b JOIN rpt.Match AS m ON m.MatchId = b.MatchId WHERE m.BallByBallStatus = 'Held');

INSERT @r SELECT 'BR26', N'Points table: points <> 2 x won + tied + no result, or positions not 1..n per season', 0,
    (SELECT COUNT(*) FROM rpt.PointsTable WHERE Points <> 2 * Won + Tied + NoResult OR Played <> Won + Lost + Tied + NoResult)
  + (SELECT COUNT(*) FROM (SELECT Season FROM rpt.PointsTable GROUP BY Season
                           HAVING MIN(Position) <> 1 OR MAX(Position) <> COUNT(*) OR COUNT(DISTINCT Position) <> COUNT(*)) AS x);

-- ---- Slowly changing dimension
INSERT @r SELECT 'BR23', N'Team codes without exactly one current Dim_Team version', 0,
    (SELECT COUNT(*) FROM (SELECT TeamCode FROM dw.Dim_Team GROUP BY TeamCode HAVING SUM(CAST(IsCurrent AS INT)) <> 1) AS x);
INSERT @r SELECT 'BR24', N'Overlapping Dim_Team versions', 0,
    (SELECT COUNT(*) FROM dw.Dim_Team AS a JOIN dw.Dim_Team AS b
       ON b.TeamCode = a.TeamCode AND b.TeamKey > a.TeamKey
      AND a.EffectiveFrom < ISNULL(b.EffectiveTo, '9999-12-31') AND b.EffectiveFrom < ISNULL(a.EffectiveTo, '9999-12-31'));
INSERT @r SELECT 'BR25', N'Match linked to a team version not valid on the match date', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult AS fm JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
     JOIN dw.Dim_Team AS t ON t.TeamKey IN (fm.Team1Key, fm.Team2Key)
     WHERE d.FullDate < t.EffectiveFrom OR d.FullDate > ISNULL(t.EffectiveTo, '9999-12-31'));

SELECT 'Business rules' AS Suite, CheckId, CheckName, Expected, Actual,
       CASE WHEN Expected = Actual THEN 'PASS' ELSE 'FAIL' END AS Result
FROM @r ORDER BY CheckId;
