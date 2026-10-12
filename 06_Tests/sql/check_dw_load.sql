-- Checks the warehouse after workflow 05_transform_load. Expected values are for a first load of the baseline
-- sample data (04 then 05 against an empty warehouse); see 06_Tests/test_cases/dw_test_cases.md.
USE CricketDW;
SET NOCOUNT ON;

-- 1. Row counts.  expect Dim_MatchFormat 4, Dim_Venue 8, Dim_Player 152, Dim_Team 9, Fact_MatchResult 119,
--    Fact_Innings 233, Fact_BallByBall 28069, Fact_BattingPerformance 2046, Fact_BowlingPerformance 1246,
--    Fact_Partnership 1839, Fact_FallOfWicket 1673, Agg_OverSummary 4424, Bridge_PlayerTeamSeason 394,
--    Fact_PlayerRanking 756, Fact_PlayerSeasonStats 395
SELECT 'Dim_MatchFormat' AS TableName, COUNT(*) AS Rows_ FROM dw.Dim_MatchFormat
UNION ALL SELECT 'Dim_Venue', COUNT(*) FROM dw.Dim_Venue
UNION ALL SELECT 'Dim_Player', COUNT(*) FROM dw.Dim_Player
UNION ALL SELECT 'Dim_Team', COUNT(*) FROM dw.Dim_Team
UNION ALL SELECT 'Fact_MatchResult', COUNT(*) FROM dw.Fact_MatchResult
UNION ALL SELECT 'Fact_Innings', COUNT(*) FROM dw.Fact_Innings
UNION ALL SELECT 'Fact_BallByBall', COUNT(*) FROM dw.Fact_BallByBall
UNION ALL SELECT 'Fact_BattingPerformance', COUNT(*) FROM dw.Fact_BattingPerformance
UNION ALL SELECT 'Fact_BowlingPerformance', COUNT(*) FROM dw.Fact_BowlingPerformance
UNION ALL SELECT 'Fact_Partnership', COUNT(*) FROM dw.Fact_Partnership
UNION ALL SELECT 'Fact_FallOfWicket', COUNT(*) FROM dw.Fact_FallOfWicket
UNION ALL SELECT 'Agg_OverSummary', COUNT(*) FROM dw.Agg_OverSummary
UNION ALL SELECT 'Bridge_PlayerTeamSeason', COUNT(*) FROM dw.Bridge_PlayerTeamSeason
UNION ALL SELECT 'Fact_PlayerRanking', COUNT(*) FROM dw.Fact_PlayerRanking
UNION ALL SELECT 'Fact_PlayerSeasonStats', COUNT(*) FROM dw.Fact_PlayerSeasonStats;

-- 2. Every derived fact reconciles with the innings scorecard (expect 0 rows): runs from ball-by-ball,
--    partnerships and over summary; wickets from ball-by-ball, fall of wicket and over summary.
WITH b  AS (SELECT MatchKey, InningsNo, SUM(RunsOffBat + ExtraRuns) AS runs, SUM(CAST(IsWicket AS INT)) AS wkts FROM dw.Fact_BallByBall GROUP BY MatchKey, InningsNo),
     pt AS (SELECT MatchKey, InningsNo, SUM(RunsAdded) AS runs FROM dw.Fact_Partnership GROUP BY MatchKey, InningsNo),
     fw AS (SELECT MatchKey, InningsNo, COUNT(*) AS wkts FROM dw.Fact_FallOfWicket GROUP BY MatchKey, InningsNo),
     ov AS (SELECT MatchKey, InningsNo, SUM(RunsInOver) AS runs, SUM(WicketsInOver) AS wkts FROM dw.Agg_OverSummary GROUP BY MatchKey, InningsNo)
SELECT b.MatchKey, b.InningsNo, i.RunsScored, b.runs AS BallRuns, pt.runs AS PartnershipRuns, ov.runs AS OverRuns,
       i.WicketsLost, b.wkts AS BallWickets, fw.wkts AS FallOfWickets
FROM b
JOIN dw.Fact_Innings AS i ON i.MatchKey = b.MatchKey AND i.InningsNo = b.InningsNo
LEFT JOIN pt ON pt.MatchKey = b.MatchKey AND pt.InningsNo = b.InningsNo
LEFT JOIN fw ON fw.MatchKey = b.MatchKey AND fw.InningsNo = b.InningsNo
LEFT JOIN ov ON ov.MatchKey = b.MatchKey AND ov.InningsNo = b.InningsNo
WHERE i.RunsScored <> b.runs OR ISNULL(pt.runs, -1) <> b.runs OR ov.runs <> b.runs
   OR i.WicketsLost <> b.wkts OR ISNULL(fw.wkts, 0) <> b.wkts OR ov.wkts <> b.wkts;

-- 3. Batting dismissals vs wickets. Expect exactly 14 innings, each one where the source dismisses the same
--    batsman twice (DQ rule batsman_dismissed_twice, Flagged): a batsman can only be out once in the facts.
WITH b  AS (SELECT MatchKey, InningsNo, SUM(CAST(IsWicket AS INT)) AS wkts FROM dw.Fact_BallByBall GROUP BY MatchKey, InningsNo),
     bt AS (SELECT MatchKey, InningsNo, SUM(IIF(IsNotOut = 0, 1, 0)) AS outs FROM dw.Fact_BattingPerformance GROUP BY MatchKey, InningsNo)
SELECT COUNT(*) AS InningsWithFewerDismissals
FROM b JOIN bt ON bt.MatchKey = b.MatchKey AND bt.InningsNo = b.InningsNo
WHERE bt.outs <> b.wkts;

-- 4. Dim_Team Type-2: DEL renamed between 2023 and 2024.
--    expect 'Delhi Falcons' 1900-01-01 to 2024-04-08 (not current), 'Delhi Comets' from 2024-04-09 (current);
--    2023 matches resolve to Delhi Falcons (8), 2024 and 2025 to Delhi Comets (9 and 9).
SELECT TeamKey, TeamCode, TeamName, EffectiveFrom, EffectiveTo, IsCurrent FROM dw.Dim_Team WHERE TeamCode = 'DEL';
SELECT fm.Season, t.TeamName, COUNT(*) AS Matches
FROM dw.Fact_MatchResult AS fm JOIN dw.Dim_Team AS t ON t.TeamKey IN (fm.Team1Key, fm.Team2Key)
WHERE t.TeamCode = 'DEL' GROUP BY fm.Season, t.TeamName ORDER BY fm.Season;

-- 5. Bridge: players are attached to the team version of the season they played in.
--    expect 2023 Delhi Falcons 16, 2024 Delhi Comets 16, 2025 Delhi Comets 15
SELECT b.Season, t.TeamName, COUNT(*) AS Players
FROM dw.Bridge_PlayerTeamSeason AS b JOIN dw.Dim_Team AS t ON t.TeamKey = b.TeamKey
WHERE t.TeamCode = 'DEL' GROUP BY b.Season, t.TeamName ORDER BY b.Season;

-- 6. Completeness: held matches carry no ball-by-ball facts.
--    expect M0001 Complete/Held, M0006 Incomplete/Held, M0008 Incomplete/Held (0 balls each), M0061 Complete/NULL (abandoned)
SELECT fm.MatchId, fm.InningsStatus, fm.BallByBallStatus,
       (SELECT COUNT(*) FROM dw.Fact_BallByBall AS x WHERE x.MatchKey = fm.MatchKey) AS Balls,
       (SELECT COUNT(*) FROM dw.Fact_Innings AS x WHERE x.MatchKey = fm.MatchKey) AS Innings
FROM dw.Fact_MatchResult AS fm
WHERE ISNULL(fm.InningsStatus, '') <> 'Complete' OR ISNULL(fm.BallByBallStatus, '') <> 'Loaded'
ORDER BY fm.MatchId;

-- 7. Rejected data never reached the warehouse (expect 0 rows).
SELECT 'M0013 loaded' AS Leak FROM dw.Fact_MatchResult WHERE MatchId = 'M0013'
UNION ALL SELECT 'Ball-by-ball of a held match' FROM dw.Fact_BallByBall AS b JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = b.MatchKey WHERE fm.BallByBallStatus = 'Held'
UNION ALL SELECT 'Future date of birth' FROM dw.Dim_Player WHERE DateOfBirth > CAST(GETDATE() AS date);

-- 8. Partnerships whose partner never faced a ball (Player2Key NULL).  expect 1839 partnerships, 103 unknown partner
SELECT COUNT(*) AS Partnerships, SUM(IIF(Player2Key IS NULL, 1, 0)) AS UnknownPartner FROM dw.Fact_Partnership;

-- 9. Queue consumed by the publish (expect 0 everywhere; PlayersValid is a full snapshot, not a queue) and load cleared.
SELECT (SELECT COUNT(*) FROM stg.MatchValid) AS MatchValid, (SELECT COUNT(*) FROM stg.InningsValid) AS InningsValid,
       (SELECT COUNT(*) FROM stg.BallByBallValid) AS BallByBallValid, (SELECT COUNT(*) FROM stg.MatchCompletenessValid) AS CompletenessValid,
       (SELECT COUNT(*) FROM stg.LoadReady_Control) AS LoadControl, (SELECT COUNT(*) FROM stg.LoadReady_BallByBall) AS LoadBallByBall;

-- 10. What the latest publish did, per table.
SELECT TableName, Operation, RowsAffected
FROM audit.Audit_PublishLog WHERE LoadRunId = (SELECT MAX(LoadRunId) FROM audit.Audit_PublishLog)
ORDER BY PublishLogId;
