-- Checks the rpt reporting layer (03_Alteryx/reporting_views/rpt_reporting_views.sql) against the warehouse
-- facts and the business rules in 07_Docs/business_rules.md. Every check returns one row: Check, Expected,
-- Actual, Result. Expected values are for the baseline load (see 06_Tests/test_cases/rpt_test_cases.md).
USE CricketDW;
SET NOCOUNT ON;

WITH checks (CheckName, Expected, Actual) AS (
    -- Row counts: one row per stated grain
    SELECT 'rpt.Match = one row per match', (SELECT COUNT(*) FROM dw.Fact_MatchResult), (SELECT COUNT(*) FROM rpt.Match)
    UNION ALL SELECT 'rpt.TeamMatch = two rows per match', 2 * (SELECT COUNT(*) FROM dw.Fact_MatchResult), (SELECT COUNT(*) FROM rpt.TeamMatch)
    UNION ALL SELECT 'rpt.BattingInnings = batting facts', (SELECT COUNT(*) FROM dw.Fact_BattingPerformance), (SELECT COUNT(*) FROM rpt.BattingInnings)
    UNION ALL SELECT 'rpt.BowlingInnings = bowling facts', (SELECT COUNT(*) FROM dw.Fact_BowlingPerformance), (SELECT COUNT(*) FROM rpt.BowlingInnings)
    UNION ALL SELECT 'rpt.Partnership = partnership facts', (SELECT COUNT(*) FROM dw.Fact_Partnership), (SELECT COUNT(*) FROM rpt.Partnership)
    UNION ALL SELECT 'rpt.OverProgression = over summary', (SELECT COUNT(*) FROM dw.Agg_OverSummary), (SELECT COUNT(*) FROM rpt.OverProgression)

    -- Totals reconcile with the facts (nothing lost or double-counted by a join)
    UNION ALL SELECT 'Batting runs: BattingInnings = facts', (SELECT SUM(RunsScored) FROM dw.Fact_BattingPerformance), (SELECT SUM(RunsScored) FROM rpt.BattingInnings)
    UNION ALL SELECT 'Batting runs: PlayerSeason = facts', (SELECT SUM(RunsScored) FROM dw.Fact_BattingPerformance), (SELECT SUM(Runs) FROM rpt.PlayerSeason)
    UNION ALL SELECT 'Batting runs: PlayerCareer = facts', (SELECT SUM(RunsScored) FROM dw.Fact_BattingPerformance), (SELECT SUM(Runs) FROM rpt.PlayerCareer)
    UNION ALL SELECT 'Batting runs: PlayerPhase = ball-by-ball', (SELECT SUM(CAST(RunsOffBat AS INT)) FROM dw.Fact_BallByBall), (SELECT SUM(Runs) FROM rpt.PlayerPhase WHERE Discipline = 'Batting')
    UNION ALL SELECT 'Wickets: PlayerSeason = bowling facts', (SELECT SUM(CAST(Wickets AS INT)) FROM dw.Fact_BowlingPerformance), (SELECT SUM(Wickets) FROM rpt.PlayerSeason)
    UNION ALL SELECT 'Wickets: PlayerPhase = bowling facts', (SELECT SUM(CAST(Wickets AS INT)) FROM dw.Fact_BowlingPerformance), (SELECT SUM(Wickets) FROM rpt.PlayerPhase WHERE Discipline = 'Bowling')
    UNION ALL SELECT 'Runs conceded: PlayerPhase = bowling facts', (SELECT SUM(RunsConceded) FROM dw.Fact_BowlingPerformance), (SELECT SUM(Runs) FROM rpt.PlayerPhase WHERE Discipline = 'Bowling')
    UNION ALL SELECT 'Team runs: TeamMatch = innings facts', (SELECT SUM(RunsScored) FROM dw.Fact_Innings), (SELECT SUM(RunsScored) FROM rpt.TeamMatch)
    UNION ALL SELECT 'TeamSeason played = TeamMatch rows', (SELECT COUNT(*) FROM rpt.TeamMatch), (SELECT SUM(Played) FROM rpt.TeamSeason)
    UNION ALL SELECT 'Innings final score = last over cumulative', 0,
        (SELECT COUNT(*) FROM (SELECT MatchId, InningsNo, MAX(CumulativeRuns) AS r FROM rpt.OverProgression GROUP BY MatchId, InningsNo) AS o
         JOIN rpt.Match AS m ON m.MatchId = o.MatchId
         JOIN dw.Fact_MatchResult AS fm ON fm.MatchId = o.MatchId
         JOIN dw.Fact_Innings AS i ON i.MatchKey = fm.MatchKey AND i.InningsNo = o.InningsNo
         WHERE i.RunsScored <> o.r)

    -- Results: every decided match with a winner has exactly one Won and one Lost
    UNION ALL SELECT 'Matches with a winner: one Won + one Lost', 0,
        (SELECT COUNT(*) FROM (SELECT MatchId FROM rpt.TeamMatch GROUP BY MatchId
                               HAVING SUM(CASE WHEN Result = 'Won' THEN 1 ELSE 0 END) = 1 AND SUM(CASE WHEN Result = 'Lost' THEN 1 ELSE 0 END) <> 1) AS x)
    UNION ALL SELECT 'Wins = matches with a winner', (SELECT COUNT(*) FROM dw.Fact_MatchResult WHERE WinnerTeamKey IS NOT NULL), (SELECT SUM(Won) FROM rpt.TeamSeason)
    UNION ALL SELECT 'Tied rows (2 tied matches x 2 teams)', 4, (SELECT SUM(Tied) FROM rpt.TeamSeason)
    UNION ALL SELECT 'No-result rows (NoResult + Abandoned x 2 teams)', 4, (SELECT SUM(NoResult) FROM rpt.TeamSeason)

    -- Business-rule guards
    UNION ALL SELECT 'Strike rate NULL when no ball faced (no divide-by-zero)', 0, (SELECT COUNT(*) FROM rpt.BattingInnings WHERE BallsFaced = 0 AND StrikeRate IS NOT NULL)
    UNION ALL SELECT 'Batting average NULL when never dismissed', 0, (SELECT COUNT(*) FROM rpt.PlayerCareer WHERE Dismissals = 0 AND BattingAverage IS NOT NULL)
    UNION ALL SELECT 'Economy = runs x 6 / legal balls', 0,
        (SELECT COUNT(*) FROM rpt.BowlingInnings WHERE LegalBalls > 0 AND ABS(Economy - CAST(RunsConceded AS DECIMAL(12,4)) * 6 / LegalBalls) > 0.01)
    UNION ALL SELECT 'Win % within 0-100', 0, (SELECT COUNT(*) FROM rpt.TeamSeason WHERE WinPct < 0 OR WinPct > 100)
    UNION ALL SELECT 'Overs <-> balls round trip (23 balls = 3.5)', 23, rpt.fn_BallsFromOvers(rpt.fn_OversFromBalls(23))
    UNION ALL SELECT 'Phases are Powerplay / Middle / Death only', 0, (SELECT COUNT(*) FROM rpt.OverProgression WHERE Phase NOT IN ('Powerplay', 'Middle', 'Death'))

    -- Data quality carried through: held matches show no ball-level statistics, and incomplete matches are flagged
    UNION ALL SELECT 'Held matches have no batting rows', 0,
        (SELECT COUNT(*) FROM rpt.BattingInnings AS b JOIN rpt.Match AS m ON m.MatchId = b.MatchId WHERE m.BallByBallStatus = 'Held')
    UNION ALL SELECT 'Matches flagged incomplete (held; abandoned M0061 is complete)', 3, (SELECT COUNT(*) FROM rpt.Match WHERE IsComplete = 0)

    -- SCD2 in reporting: names as at the match, current name for trends across the rename
    UNION ALL SELECT 'DEL 2023 rows carry the 2023 name', 0, (SELECT COUNT(*) FROM rpt.TeamMatch WHERE TeamCode = 'DEL' AND Season = '2023' AND TeamName <> 'Delhi Falcons')
    UNION ALL SELECT 'DEL current name on every season', 0, (SELECT COUNT(*) FROM rpt.TeamSeason WHERE TeamCode = 'DEL' AND TeamCurrentName <> 'Delhi Comets')
)
SELECT CheckName, Expected, Actual, CASE WHEN Expected = Actual THEN 'PASS' ELSE 'FAIL' END AS Result
FROM checks;
