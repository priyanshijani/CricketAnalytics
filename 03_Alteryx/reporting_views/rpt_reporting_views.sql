-- CricketDW.rpt: the reporting layer - the only objects workflow 06 exports and the reporting login can read.
--
-- Business rules are defined ONCE, as functions at the top of this script (see 07_Docs/business_rules.md);
-- every view calls them, so a dashboard, the CSV export and an ad hoc query can never disagree on a formula.
-- Each view states its grain. Ball-level statistics (batting, bowling, phases, partnerships) exclude matches
-- whose ball-by-ball is Held by the DQ gate (see Fact_MatchResult.BallByBallStatus).
-- Idempotent: safe to re-run.

USE CricketDW;
GO
IF SCHEMA_ID(N'rpt') IS NULL EXEC(N'CREATE SCHEMA rpt AUTHORIZATION dbo');
GO

-- ===========================================================================
-- Business rules
-- ===========================================================================

-- Batting average = runs / times dismissed. NULL when never dismissed (cricket convention: not "infinite").
CREATE OR ALTER FUNCTION rpt.fn_BattingAverage (@Runs INT, @Dismissals INT)
RETURNS DECIMAL(9,2) WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN @Dismissals > 0 THEN CAST(@Runs AS DECIMAL(12,2)) / @Dismissals END; END;
GO

-- Batting strike rate = runs per 100 balls faced. NULL when no balls faced (guards divide-by-zero).
CREATE OR ALTER FUNCTION rpt.fn_StrikeRate (@Runs INT, @BallsFaced INT)
RETURNS DECIMAL(9,2) WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN @BallsFaced > 0 THEN CAST(@Runs AS DECIMAL(12,2)) * 100 / @BallsFaced END; END;
GO

-- Overs in cricket notation (3.5 = 3 overs and 5 balls) converted to legal balls.
CREATE OR ALTER FUNCTION rpt.fn_BallsFromOvers (@Overs DECIMAL(5,1))
RETURNS INT WITH SCHEMABINDING AS
BEGIN RETURN CAST(FLOOR(@Overs) AS INT) * 6 + CAST(ROUND((@Overs - FLOOR(@Overs)) * 10, 0) AS INT); END;
GO

-- Legal balls converted back to cricket notation (23 balls = 3.5).
CREATE OR ALTER FUNCTION rpt.fn_OversFromBalls (@Balls INT)
RETURNS DECIMAL(6,1) WITH SCHEMABINDING AS
BEGIN RETURN CAST(@Balls / 6 AS DECIMAL(6,1)) + CAST(@Balls % 6 AS DECIMAL(6,1)) / 10; END;
GO

-- Bowling economy = runs conceded per over (6 legal balls). NULL when no legal ball bowled.
CREATE OR ALTER FUNCTION rpt.fn_Economy (@RunsConceded INT, @LegalBalls INT)
RETURNS DECIMAL(9,2) WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN @LegalBalls > 0 THEN CAST(@RunsConceded AS DECIMAL(12,2)) * 6 / @LegalBalls END; END;
GO

-- Bowling average = runs conceded per wicket. NULL when no wicket taken.
CREATE OR ALTER FUNCTION rpt.fn_BowlingAverage (@RunsConceded INT, @Wickets INT)
RETURNS DECIMAL(9,2) WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN @Wickets > 0 THEN CAST(@RunsConceded AS DECIMAL(12,2)) / @Wickets END; END;
GO

-- Win percentage = wins / decided matches * 100. A decided match has a result: ties and super-over matches
-- count (a super over has a winner; a tie is decided without one); no-results and abandoned matches do not.
CREATE OR ALTER FUNCTION rpt.fn_WinPct (@Won INT, @Decided INT)
RETURNS DECIMAL(5,2) WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN @Decided > 0 THEN CAST(@Won AS DECIMAL(9,2)) * 100 / @Decided END; END;
GO

-- Match phase of an over (T20): Powerplay overs 1-6, Middle overs 7-15, Death overs 16-20.
CREATE OR ALTER FUNCTION rpt.fn_Phase (@OverNo INT)
RETURNS VARCHAR(10) WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN @OverNo <= 6 THEN 'Powerplay' WHEN @OverNo <= 15 THEN 'Middle' ELSE 'Death' END; END;
GO

-- Home match: the venue code starts with the team code (venues are coded <team><nn>, e.g. MUM01).
-- An assumption of this dataset - Dim_Venue has no home-team attribute.
CREATE OR ALTER FUNCTION rpt.fn_IsHome (@TeamCode VARCHAR(10), @VenueCode VARCHAR(20))
RETURNS BIT WITH SCHEMABINDING AS
BEGIN RETURN CASE WHEN LEFT(@VenueCode, LEN(@TeamCode)) = @TeamCode THEN 1 ELSE 0 END; END;
GO

-- Combined all-rounder contribution of one performance: runs + 20 points per wicket.
CREATE OR ALTER FUNCTION rpt.fn_ImpactPoints (@Runs INT, @Wickets INT)
RETURNS INT WITH SCHEMABINDING AS
BEGIN RETURN ISNULL(@Runs, 0) + 20 * ISNULL(@Wickets, 0); END;
GO

-- ===========================================================================
-- Match level
-- ===========================================================================

-- Grain: one row per match.
CREATE OR ALTER VIEW rpt.Match AS
SELECT fm.MatchId, d.FullDate AS MatchDate, fm.Season, f.FormatCode, f.FormatName,
       -- dashboard match picker: 'M0002 | 2023-04-02 | MUM v CHE' (the workbook matches on the part before the first ' | ')
       fm.MatchId + ' | ' + CONVERT(CHAR(10), d.FullDate, 23) + ' | ' + t1.TeamCode + ' v ' + t2.TeamCode AS MatchLabel,
       v.VenueCode, v.VenueName, v.City,
       t1.TeamCode AS Team1Code, t1.TeamName AS Team1Name, t2.TeamCode AS Team2Code, t2.TeamName AS Team2Name,
       tw.TeamCode AS TossWinnerCode, tw.TeamName AS TossWinnerName, fm.TossDecision,
       w.TeamCode AS WinnerCode, w.TeamName AS WinnerName, fm.ResultMethod, fm.WinMargin, fm.WinMarginType,
       mom.FullName AS ManOfMatch,
       i1.RunsScored AS Team1Runs, i1.WicketsLost AS Team1Wickets, i1.OversPlayed AS Team1Overs,
       i2.RunsScored AS Team2Runs, i2.WicketsLost AS Team2Wickets, i2.OversPlayed AS Team2Overs,
       bf.TeamCode AS BattingFirstCode,
       CASE WHEN fm.WinnerTeamKey IS NULL THEN NULL WHEN fm.WinnerTeamKey = fm.TossWinnerTeamKey THEN 1 ELSE 0 END AS TossWinnerWonMatch,
       CASE WHEN fm.WinnerTeamKey IS NULL OR bfi.BattingTeamKey IS NULL THEN NULL
            WHEN fm.WinnerTeamKey = bfi.BattingTeamKey THEN 1 ELSE 0 END AS BattingFirstWon,
       fm.InningsStatus, fm.BallByBallStatus,
       CASE WHEN ISNULL(fm.InningsStatus, 'Complete') = 'Complete' AND ISNULL(fm.BallByBallStatus, 'Loaded') = 'Loaded' THEN 1 ELSE 0 END AS IsComplete
FROM dw.Fact_MatchResult AS fm
JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
JOIN dw.Dim_MatchFormat AS f ON f.FormatKey = fm.FormatKey
JOIN dw.Dim_Venue AS v ON v.VenueKey = fm.VenueKey
JOIN dw.Dim_Team AS t1 ON t1.TeamKey = fm.Team1Key
JOIN dw.Dim_Team AS t2 ON t2.TeamKey = fm.Team2Key
LEFT JOIN dw.Dim_Team AS tw ON tw.TeamKey = fm.TossWinnerTeamKey
LEFT JOIN dw.Dim_Team AS w ON w.TeamKey = fm.WinnerTeamKey
LEFT JOIN dw.Dim_Player AS mom ON mom.PlayerKey = fm.ManOfMatchPlayerKey
LEFT JOIN dw.Fact_Innings AS i1 ON i1.MatchKey = fm.MatchKey AND i1.BattingTeamKey = fm.Team1Key
LEFT JOIN dw.Fact_Innings AS i2 ON i2.MatchKey = fm.MatchKey AND i2.BattingTeamKey = fm.Team2Key
LEFT JOIN dw.Fact_Innings AS bfi ON bfi.MatchKey = fm.MatchKey AND bfi.InningsNo = 1
LEFT JOIN dw.Dim_Team AS bf ON bf.TeamKey = bfi.BattingTeamKey;
GO

-- Grain: one row per team per match (two rows per match). The basis of every team statistic.
CREATE OR ALTER VIEW rpt.TeamMatch AS
WITH side AS (
    SELECT MatchKey, Team1Key AS TeamKey, Team2Key AS OpponentKey FROM dw.Fact_MatchResult
    UNION ALL
    SELECT MatchKey, Team2Key, Team1Key FROM dw.Fact_MatchResult
)
SELECT fm.MatchId, d.FullDate AS MatchDate, fm.Season, f.FormatCode, v.VenueCode, v.VenueName, v.City,
       t.TeamCode, t.TeamName, tc.TeamName AS TeamCurrentName,
       o.TeamCode AS OpponentCode, o.TeamName AS OpponentName, oc.TeamName AS OpponentCurrentName,
       CASE WHEN fm.ResultMethod IN ('NoResult', 'Abandoned') THEN fm.ResultMethod
            WHEN fm.WinnerTeamKey = s.TeamKey THEN 'Won'
            WHEN fm.WinnerTeamKey = s.OpponentKey THEN 'Lost'
            ELSE 'Tied' END AS Result,
       CASE WHEN fm.WinnerTeamKey = s.TeamKey THEN 1 ELSE 0 END AS IsWin,
       CASE WHEN fm.ResultMethod IN ('NoResult', 'Abandoned') THEN 0 ELSE 1 END AS IsDecided,
       fm.ResultMethod, fm.WinMargin, fm.WinMarginType,
       bat.RunsScored, bat.WicketsLost, bat.OversPlayed, bowl.RunsScored AS RunsConceded, bowl.WicketsLost AS WicketsTaken,
       CASE WHEN fm.TossWinnerTeamKey = s.TeamKey THEN 1 ELSE 0 END AS WonToss,
       CASE WHEN bat.InningsNo = 1 THEN 1 WHEN bat.InningsNo = 2 THEN 0 END AS BattedFirst,
       rpt.fn_IsHome(t.TeamCode, v.VenueCode) AS IsHome,
       ROW_NUMBER() OVER (PARTITION BY t.TeamCode, fm.Season ORDER BY d.FullDate, fm.MatchId) AS SeasonMatchNo,
       -- within-season form (question 2): wins / decided matches so far this season, after this match (0-1).
       -- Cast the result: a DECIMAL division widens to precision 38, which a Tableau .hyper cannot store (max 18).
       CAST(CAST(SUM(CASE WHEN fm.WinnerTeamKey = s.TeamKey THEN 1 ELSE 0 END)
                     OVER (PARTITION BY t.TeamCode, fm.Season ORDER BY d.FullDate, fm.MatchId ROWS UNBOUNDED PRECEDING) AS DECIMAL(9,4))
              / NULLIF(SUM(CASE WHEN fm.ResultMethod IN ('NoResult', 'Abandoned') THEN 0 ELSE 1 END)
                     OVER (PARTITION BY t.TeamCode, fm.Season ORDER BY d.FullDate, fm.MatchId ROWS UNBOUNDED PRECEDING), 0)
            AS DECIMAL(9,4)) AS RunningWinPct,
       CASE WHEN ISNULL(fm.InningsStatus, 'Complete') = 'Complete' AND ISNULL(fm.BallByBallStatus, 'Loaded') = 'Loaded' THEN 1 ELSE 0 END AS IsComplete
FROM side AS s
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = s.MatchKey
JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
JOIN dw.Dim_MatchFormat AS f ON f.FormatKey = fm.FormatKey
JOIN dw.Dim_Venue AS v ON v.VenueKey = fm.VenueKey
JOIN dw.Dim_Team AS t ON t.TeamKey = s.TeamKey
JOIN dw.Dim_Team AS o ON o.TeamKey = s.OpponentKey
JOIN dw.Dim_Team AS tc ON tc.TeamCode = t.TeamCode AND tc.IsCurrent = 1
JOIN dw.Dim_Team AS oc ON oc.TeamCode = o.TeamCode AND oc.IsCurrent = 1
LEFT JOIN dw.Fact_Innings AS bat ON bat.MatchKey = s.MatchKey AND bat.BattingTeamKey = s.TeamKey
LEFT JOIN dw.Fact_Innings AS bowl ON bowl.MatchKey = s.MatchKey AND bowl.BattingTeamKey = s.OpponentKey;
GO

-- Grain: one row per team per season.
CREATE OR ALTER VIEW rpt.TeamSeason AS
SELECT TeamCode, MAX(TeamCurrentName) AS TeamCurrentName, Season,
       COUNT(*) AS Played, SUM(IsWin) AS Won,
       SUM(CASE WHEN Result = 'Lost' THEN 1 ELSE 0 END) AS Lost,
       SUM(CASE WHEN Result = 'Tied' THEN 1 ELSE 0 END) AS Tied,
       SUM(CASE WHEN IsDecided = 0 THEN 1 ELSE 0 END) AS NoResult,
       rpt.fn_WinPct(SUM(IsWin), SUM(IsDecided)) AS WinPct,
       SUM(RunsScored) AS RunsScored, SUM(RunsConceded) AS RunsConceded,
       SUM(CAST(IsHome AS INT)) AS HomeMatches, SUM(CASE WHEN IsHome = 1 THEN IsWin ELSE 0 END) AS HomeWins
FROM rpt.TeamMatch
GROUP BY TeamCode, Season;
GO

-- Grain: one row per season plus 'All seasons' - the list behind the dashboards' season filter (a Tableau
-- parameter reads its values from here when the workbook opens, so a new season appears without editing it).
CREATE OR ALTER VIEW rpt.SeasonList AS
SELECT CAST('All seasons' AS VARCHAR(20)) AS Season, 0 AS SortOrder
UNION ALL
SELECT DISTINCT CAST(Season AS VARCHAR(20)), 1 FROM rpt.Match;
GO

-- Grain: one row per team per season - the IPL-style points table (Leaderboard dashboard).
--   Points: 2 for a win (a super-over win included), 1 for a tie, no result or abandoned match, 0 for a loss.
--   Net run rate: runs scored per over faced minus runs conceded per over bowled, over the matches with a result;
--   a side bowled out counts its full 20 overs (IPL rule). No-result and abandoned matches do not count.
--   Position: points, then net run rate, then wins. Form: the last five results, oldest first.
--   PositionLabel: trophy / silver / bronze for the top three (emoji built with NCHAR so the script stays ASCII).
CREATE OR ALTER VIEW rpt.PointsTable AS
WITH m AS (
    SELECT t.Season, t.TeamCode, t.TeamCurrentName, t.SeasonMatchNo, t.Result,
           CASE t.Result WHEN 'Won' THEN 2 WHEN 'Lost' THEN 0 ELSE 1 END AS Pts,
           CASE WHEN t.Result IN ('NoResult', 'Abandoned') THEN 0 ELSE 1 END AS HasResult,
           t.RunsScored, t.RunsConceded,
           CASE WHEN t.WicketsLost = 10 THEN 120 ELSE rpt.fn_BallsFromOvers(t.OversPlayed) END AS BallsFaced,
           CASE WHEN o.WicketsLost = 10 THEN 120 ELSE rpt.fn_BallsFromOvers(o.OversPlayed) END AS BallsBowled
    FROM rpt.TeamMatch AS t
    JOIN rpt.TeamMatch AS o ON o.MatchId = t.MatchId AND o.TeamCode = t.OpponentCode
),
s AS (
    SELECT Season, TeamCode, MAX(TeamCurrentName) AS TeamCurrentName, COUNT(*) AS Played,
           SUM(CASE WHEN Result = 'Won' THEN 1 ELSE 0 END) AS Won,
           SUM(CASE WHEN Result = 'Lost' THEN 1 ELSE 0 END) AS Lost,
           SUM(CASE WHEN Result = 'Tied' THEN 1 ELSE 0 END) AS Tied,
           SUM(CASE WHEN Result IN ('NoResult', 'Abandoned') THEN 1 ELSE 0 END) AS NoResult,
           SUM(Pts) AS Points,
           CAST(SUM(CASE WHEN HasResult = 1 THEN RunsScored END) * 6.0 / NULLIF(SUM(CASE WHEN HasResult = 1 THEN BallsFaced END), 0)
              - SUM(CASE WHEN HasResult = 1 THEN RunsConceded END) * 6.0 / NULLIF(SUM(CASE WHEN HasResult = 1 THEN BallsBowled END), 0)
                AS DECIMAL(6,3)) AS NetRunRate
    FROM m
    GROUP BY Season, TeamCode
),
f AS (
    SELECT Season, TeamCode,
           STRING_AGG(CASE Result WHEN 'Won' THEN 'W' WHEN 'Lost' THEN 'L' WHEN 'Tied' THEN 'T' ELSE 'NR' END, ' ')
               WITHIN GROUP (ORDER BY SeasonMatchNo) AS Form
    FROM (SELECT Season, TeamCode, SeasonMatchNo, Result,
                 ROW_NUMBER() OVER (PARTITION BY Season, TeamCode ORDER BY SeasonMatchNo DESC) AS rn FROM m) AS x
    WHERE rn <= 5
    GROUP BY Season, TeamCode
),
r AS (
    SELECT s.*, f.Form,
           CAST(ROW_NUMBER() OVER (PARTITION BY s.Season ORDER BY s.Points DESC, s.NetRunRate DESC, s.Won DESC, s.TeamCode) AS INT) AS Position
    FROM s JOIN f ON f.Season = s.Season AND f.TeamCode = s.TeamCode
)
SELECT Season, Position,
       CAST(CASE Position WHEN 1 THEN NCHAR(55356) + NCHAR(57286)      -- trophy  U+1F3C6
                          WHEN 2 THEN NCHAR(55358) + NCHAR(56648)      -- silver  U+1F948
                          WHEN 3 THEN NCHAR(55358) + NCHAR(56649)      -- bronze  U+1F949
                          ELSE CAST(Position AS NVARCHAR(3)) END AS NVARCHAR(10)) AS PositionLabel,
       TeamCode, TeamCurrentName, Played, Won, Lost, Tied, NoResult, Points, NetRunRate,
       CAST(FORMAT(NetRunRate, '+0.000;-0.000;0.000') AS VARCHAR(10)) AS NetRunRateLabel,
       CAST(Form AS VARCHAR(20)) AS Form
FROM r;
GO

-- Grain: one row per innings (team batting), with the running score over by over (worm / manhattan charts).
CREATE OR ALTER VIEW rpt.OverProgression AS
SELECT fm.MatchId, fm.Season, o.InningsNo, bt.TeamCode AS BattingTeamCode, bt.TeamName AS BattingTeamName,
       o.OverNo, rpt.fn_Phase(o.OverNo) AS Phase, o.RunsInOver, o.WicketsInOver,
       SUM(CAST(o.RunsInOver AS INT)) OVER (PARTITION BY o.MatchKey, o.InningsNo ORDER BY o.OverNo ROWS UNBOUNDED PRECEDING) AS CumulativeRuns,
       SUM(CAST(o.WicketsInOver AS INT)) OVER (PARTITION BY o.MatchKey, o.InningsNo ORDER BY o.OverNo ROWS UNBOUNDED PRECEDING) AS CumulativeWickets
FROM dw.Agg_OverSummary AS o
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = o.MatchKey
JOIN dw.Fact_Innings AS i ON i.MatchKey = o.MatchKey AND i.InningsNo = o.InningsNo
JOIN dw.Dim_Team AS bt ON bt.TeamKey = i.BattingTeamKey;
GO

-- Grain: one row per wicket per innings.
CREATE OR ALTER VIEW rpt.FallOfWicket AS
SELECT fm.MatchId, fm.Season, w.InningsNo, bt.TeamCode AS BattingTeamCode, w.WicketNumber, w.ScoreAtFall, w.OverAtFall,
       po.PlayerCode AS PlayerOutCode, po.FullName AS PlayerOutName, bw.FullName AS BowlerName, w.DismissalType
FROM dw.Fact_FallOfWicket AS w
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = w.MatchKey
JOIN dw.Fact_Innings AS i ON i.MatchKey = w.MatchKey AND i.InningsNo = w.InningsNo
JOIN dw.Dim_Team AS bt ON bt.TeamKey = i.BattingTeamKey
JOIN dw.Dim_Player AS po ON po.PlayerKey = w.PlayerOutKey
LEFT JOIN dw.Dim_Player AS bw ON bw.PlayerKey = w.BowlerKey;
GO

-- Grain: one row per partnership (wicket number) per innings. Player2 is unknown when the partner never faced
-- a ball (ball-by-ball records only the striker).
CREATE OR ALTER VIEW rpt.Partnership AS
SELECT fm.MatchId, fm.Season, d.FullDate AS MatchDate, p.InningsNo, bt.TeamCode AS BattingTeamCode, bt.TeamName AS BattingTeamName,
       btc.TeamName AS BattingTeamCurrentName,
       p.WicketNumber, CASE WHEN p.WicketNumber = 1 THEN 1 ELSE 0 END AS IsOpeningPartnership,
       p1.FullName AS Player1Name, ISNULL(p2.FullName, 'Unknown (did not face a ball)') AS Player2Name,
       CASE WHEN p2.FullName IS NULL THEN p1.FullName
            WHEN p1.FullName < p2.FullName THEN p1.FullName + ' & ' + p2.FullName
            ELSE p2.FullName + ' & ' + p1.FullName END AS Pair,
       p.RunsAdded, p.BallsFaced,
       CASE WHEN fm.WinnerTeamKey = i.BattingTeamKey THEN 1 ELSE 0 END AS TeamWon
FROM dw.Fact_Partnership AS p
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = p.MatchKey
JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
JOIN dw.Fact_Innings AS i ON i.MatchKey = p.MatchKey AND i.InningsNo = p.InningsNo
JOIN dw.Dim_Team AS bt ON bt.TeamKey = i.BattingTeamKey
JOIN dw.Dim_Team AS btc ON btc.TeamCode = bt.TeamCode AND btc.IsCurrent = 1
JOIN dw.Dim_Player AS p1 ON p1.PlayerKey = p.Player1Key
LEFT JOIN dw.Dim_Player AS p2 ON p2.PlayerKey = p.Player2Key;
GO

-- ===========================================================================
-- Player level
-- ===========================================================================

-- Grain: one row per batsman per innings.
CREATE OR ALTER VIEW rpt.BattingInnings AS
SELECT fm.MatchId, d.FullDate AS MatchDate, fm.Season, b.InningsNo, p.PlayerCode, p.FullName AS PlayerName, p.PlayerRole,
       t.TeamCode, t.TeamName, o.TeamCode AS OpponentCode, o.TeamName AS OpponentName, v.VenueName,
       rpt.fn_IsHome(t.TeamCode, v.VenueCode) AS IsHome,
       b.RunsScored, b.BallsFaced, b.Fours, b.Sixes, b.IsNotOut, b.DismissalType, db.FullName AS DismissedBy,
       rpt.fn_StrikeRate(b.RunsScored, b.BallsFaced) AS StrikeRate,
       CASE WHEN b.RunsScored BETWEEN 50 AND 99 THEN 1 ELSE 0 END AS IsFifty,
       CASE WHEN b.RunsScored >= 100 THEN 1 ELSE 0 END AS IsHundred
FROM dw.Fact_BattingPerformance AS b
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = b.MatchKey
JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
JOIN dw.Dim_Venue AS v ON v.VenueKey = fm.VenueKey
JOIN dw.Dim_Player AS p ON p.PlayerKey = b.PlayerKey
JOIN dw.Dim_Team AS t ON t.TeamKey = b.TeamKey
JOIN dw.Dim_Team AS o ON o.TeamKey = CASE WHEN fm.Team1Key = b.TeamKey THEN fm.Team2Key ELSE fm.Team1Key END
LEFT JOIN dw.Dim_Player AS db ON db.PlayerKey = b.DismissedByPlayerKey;
GO

-- Grain: one row per bowler per innings.
CREATE OR ALTER VIEW rpt.BowlingInnings AS
SELECT fm.MatchId, d.FullDate AS MatchDate, fm.Season, b.InningsNo, p.PlayerCode, p.FullName AS PlayerName, p.PlayerRole,
       t.TeamCode, t.TeamName, o.TeamCode AS OpponentCode, o.TeamName AS OpponentName, v.VenueName,
       rpt.fn_IsHome(t.TeamCode, v.VenueCode) AS IsHome,
       b.OversBowled, rpt.fn_BallsFromOvers(b.OversBowled) AS LegalBalls, b.RunsConceded, b.Wickets, b.Maidens,
       rpt.fn_Economy(b.RunsConceded, rpt.fn_BallsFromOvers(b.OversBowled)) AS Economy
FROM dw.Fact_BowlingPerformance AS b
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = b.MatchKey
JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
JOIN dw.Dim_Venue AS v ON v.VenueKey = fm.VenueKey
JOIN dw.Dim_Player AS p ON p.PlayerKey = b.PlayerKey
JOIN dw.Dim_Team AS t ON t.TeamKey = b.TeamKey
JOIN dw.Dim_Team AS o ON o.TeamKey = CASE WHEN fm.Team1Key = b.TeamKey THEN fm.Team2Key ELSE fm.Team1Key END;
GO

-- Grain: one row per player per match (batting and bowling combined) - basis of consistency and impact.
CREATE OR ALTER VIEW rpt.PlayerMatch AS
WITH perf AS (
    SELECT MatchKey, PlayerKey, TeamKey, RunsScored AS Runs, BallsFaced, IsNotOut, 1 AS Batted,
           CAST(0 AS INT) AS Wickets, CAST(0 AS INT) AS RunsConceded, CAST(0 AS INT) AS LegalBalls, 0 AS Bowled
    FROM dw.Fact_BattingPerformance
    UNION ALL
    SELECT MatchKey, PlayerKey, TeamKey, 0, 0, NULL, 0, Wickets, RunsConceded, rpt.fn_BallsFromOvers(OversBowled), 1
    FROM dw.Fact_BowlingPerformance
)
SELECT fm.MatchId, d.FullDate AS MatchDate, fm.Season, p.PlayerCode, p.FullName AS PlayerName, p.PlayerRole,
       t.TeamCode, SUM(perf.Runs) AS Runs, SUM(perf.BallsFaced) AS BallsFaced, MAX(perf.Batted) AS Batted,
       SUM(CASE WHEN perf.Batted = 1 AND perf.IsNotOut = 0 THEN 1 ELSE 0 END) AS Dismissals,
       SUM(perf.Wickets) AS Wickets, SUM(perf.RunsConceded) AS RunsConceded, SUM(perf.LegalBalls) AS LegalBallsBowled,
       MAX(perf.Bowled) AS Bowled, rpt.fn_ImpactPoints(SUM(perf.Runs), SUM(perf.Wickets)) AS ImpactPoints
FROM perf
JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = perf.MatchKey
JOIN dw.Dim_Date AS d ON d.DateKey = fm.DateKey
JOIN dw.Dim_Player AS p ON p.PlayerKey = perf.PlayerKey
JOIN dw.Dim_Team AS t ON t.TeamKey = perf.TeamKey
GROUP BY fm.MatchId, d.FullDate, fm.Season, p.PlayerCode, p.FullName, p.PlayerRole, t.TeamCode;
GO

-- Grain: one row per player per season, with the change from the previous season (improving / declining).
CREATE OR ALTER VIEW rpt.PlayerSeason AS
WITH s AS (
    SELECT PlayerCode, MAX(PlayerName) AS PlayerName, MAX(PlayerRole) AS PlayerRole, Season,
           COUNT(*) AS Matches, SUM(Batted) AS InningsBatted, SUM(Runs) AS Runs, SUM(BallsFaced) AS BallsFaced,
           SUM(Dismissals) AS Dismissals, SUM(Bowled) AS InningsBowled, SUM(Wickets) AS Wickets,
           SUM(RunsConceded) AS RunsConceded, SUM(LegalBallsBowled) AS LegalBallsBowled, SUM(ImpactPoints) AS ImpactPoints
    FROM rpt.PlayerMatch
    GROUP BY PlayerCode, Season
)
SELECT s.*,
       rpt.fn_BattingAverage(s.Runs, s.Dismissals) AS BattingAverage,
       rpt.fn_StrikeRate(s.Runs, s.BallsFaced) AS StrikeRate,
       rpt.fn_Economy(s.RunsConceded, s.LegalBallsBowled) AS Economy,
       rpt.fn_BowlingAverage(s.RunsConceded, s.Wickets) AS BowlingAverage,
       rpt.fn_OversFromBalls(s.LegalBallsBowled) AS OversBowled,
       CAST(CAST(s.ImpactPoints AS DECIMAL(12,4)) / s.Matches AS DECIMAL(9,2)) AS ImpactPerMatch,
       s.Runs - LAG(s.Runs) OVER (PARTITION BY s.PlayerCode ORDER BY s.Season) AS RunsChangeVsPriorSeason,
       s.Wickets - LAG(s.Wickets) OVER (PARTITION BY s.PlayerCode ORDER BY s.Season) AS WicketsChangeVsPriorSeason
FROM s;
GO

-- Grain: one row per player (whole career in the data), with consistency (spread of match-to-match runs).
CREATE OR ALTER VIEW rpt.PlayerCareer AS
WITH c AS (
    SELECT PlayerCode, MAX(PlayerName) AS PlayerName, MAX(PlayerRole) AS PlayerRole,
           COUNT(*) AS Matches, SUM(Batted) AS InningsBatted, SUM(Runs) AS Runs, SUM(BallsFaced) AS BallsFaced,
           SUM(Dismissals) AS Dismissals, MAX(Runs) AS HighScore, SUM(Bowled) AS InningsBowled, SUM(Wickets) AS Wickets,
           SUM(RunsConceded) AS RunsConceded, SUM(LegalBallsBowled) AS LegalBallsBowled, SUM(ImpactPoints) AS ImpactPoints,
           STDEV(CASE WHEN Batted = 1 THEN CAST(Runs AS FLOAT) END) AS RunsStdDev,
           AVG(CASE WHEN Batted = 1 THEN CAST(Runs AS FLOAT) END) AS RunsMeanPerInnings
    FROM rpt.PlayerMatch
    GROUP BY PlayerCode
)
SELECT c.*,
       rpt.fn_BattingAverage(c.Runs, c.Dismissals) AS BattingAverage,
       rpt.fn_StrikeRate(c.Runs, c.BallsFaced) AS StrikeRate,
       rpt.fn_Economy(c.RunsConceded, c.LegalBallsBowled) AS Economy,
       rpt.fn_BowlingAverage(c.RunsConceded, c.Wickets) AS BowlingAverage,
       CAST(CAST(c.ImpactPoints AS DECIMAL(12,4)) / c.Matches AS DECIMAL(9,2)) AS ImpactPerMatch,
       CASE WHEN c.RunsMeanPerInnings > 0 AND c.InningsBatted >= 5 THEN CAST(c.RunsStdDev / c.RunsMeanPerInnings AS DECIMAL(9,2)) END AS RunsVariationCoefficient,
       (SELECT SUM(IsFifty) FROM rpt.BattingInnings AS bi WHERE bi.PlayerCode = c.PlayerCode) AS Fifties,
       (SELECT SUM(IsHundred) FROM rpt.BattingInnings AS bi WHERE bi.PlayerCode = c.PlayerCode) AS Hundreds,
       -- leaderboards: the dashboards filter "top N" on these, so a top-10 stays correct as data is added
       RANK() OVER (ORDER BY c.Runs DESC) AS RunsRank,
       RANK() OVER (ORDER BY c.Wickets DESC) AS WicketsRank,
       RANK() OVER (ORDER BY CAST(c.ImpactPoints AS DECIMAL(12,4)) / c.Matches DESC) AS ImpactRank
FROM c;
GO

-- Grain: one row per player per match phase per discipline (batting runs / strike rate, bowling economy).
CREATE OR ALTER VIEW rpt.PlayerPhase AS
WITH ball AS (
    SELECT b.*, fm.Season, rpt.fn_Phase(b.OverNo) AS Phase,
           CASE WHEN b.ExtraType = 'Wide' THEN 0 ELSE 1 END AS BallFaced,
           CASE WHEN b.ExtraType IN ('Wide', 'NoBall') THEN 0 ELSE 1 END AS LegalBall,
           b.RunsOffBat + CASE WHEN b.ExtraType IN ('Wide', 'NoBall') THEN b.ExtraRuns ELSE 0 END AS BowlerRuns,
           CASE WHEN b.IsWicket = 1 AND b.DismissalType <> 'RunOut' THEN 1 ELSE 0 END AS BowlerWicket
    FROM dw.Fact_BallByBall AS b
    JOIN dw.Fact_MatchResult AS fm ON fm.MatchKey = b.MatchKey
)
SELECT p.PlayerCode, p.FullName AS PlayerName, p.PlayerRole, ball.Season, ball.Phase, 'Batting' AS Discipline,
       SUM(CAST(ball.RunsOffBat AS INT)) AS Runs, SUM(ball.BallFaced) AS Balls, SUM(CAST(ball.IsWicket AS INT)) AS Wickets,
       rpt.fn_StrikeRate(SUM(CAST(ball.RunsOffBat AS INT)), SUM(ball.BallFaced)) AS StrikeRate, CAST(NULL AS DECIMAL(9,2)) AS Economy
FROM ball JOIN dw.Dim_Player AS p ON p.PlayerKey = ball.BatsmanPlayerKey
GROUP BY p.PlayerCode, p.FullName, p.PlayerRole, ball.Season, ball.Phase
UNION ALL
SELECT p.PlayerCode, p.FullName, p.PlayerRole, ball.Season, ball.Phase, 'Bowling',
       SUM(ball.BowlerRuns), SUM(ball.LegalBall), SUM(ball.BowlerWicket),
       CAST(NULL AS DECIMAL(9,2)), rpt.fn_Economy(SUM(ball.BowlerRuns), SUM(ball.LegalBall))
FROM ball JOIN dw.Dim_Player AS p ON p.PlayerKey = ball.BowlerPlayerKey
GROUP BY p.PlayerCode, p.FullName, p.PlayerRole, ball.Season, ball.Phase;
GO

-- Grain: one row per player per format per ranking date per discipline.
CREATE OR ALTER VIEW rpt.PlayerRanking AS
SELECT p.PlayerCode, p.FullName AS PlayerName, p.PlayerRole, f.FormatCode, r.Discipline, r.RankingDate, r.RankPosition, r.RatingPoints
FROM dw.Fact_PlayerRanking AS r
JOIN dw.Dim_Player AS p ON p.PlayerKey = r.PlayerKey
JOIN dw.Dim_MatchFormat AS f ON f.FormatKey = r.FormatKey;
GO

-- Grain: one row per player per season per format, from the historical-statistics feed.
CREATE OR ALTER VIEW rpt.PlayerSeasonHistory AS
SELECT p.PlayerCode, p.FullName AS PlayerName, p.PlayerRole, s.Season, f.FormatCode, s.MatchesPlayed, s.RunsScored, s.WicketsTaken
FROM dw.Fact_PlayerSeasonStats AS s
JOIN dw.Dim_Player AS p ON p.PlayerKey = s.PlayerKey
JOIN dw.Dim_MatchFormat AS f ON f.FormatKey = s.FormatKey;
GO

-- Grain: one row per player (attributes for filters and labels).
CREATE OR ALTER VIEW rpt.Player AS
SELECT p.PlayerCode, p.FullName AS PlayerName, p.Country, p.PlayerRole, p.BattingStyle, p.BowlingStyle, p.DateOfBirth, p.DebutDate,
       (SELECT TOP (1) t.TeamName FROM dw.Bridge_PlayerTeamSeason AS b JOIN dw.Dim_Team AS t ON t.TeamKey = b.TeamKey
        WHERE b.PlayerKey = p.PlayerKey ORDER BY b.Season DESC) AS LatestTeamName
FROM dw.Dim_Player AS p;
GO

-- ===========================================================================
-- Data quality and load status (the "Data Quality & Load Status" view)
-- ===========================================================================

-- Grain: one row per source file - the outcome of validating its content.
-- A re-run logs an unchanged file again as 'Duplicate'; that is a re-delivery, not a new outcome, so the status
-- is the latest non-duplicate row (New = loaded, Rejected). A file whose first arrival was already a copy of an
-- earlier file (e.g. M0011_redelivered.json) stays 'Duplicate'. TimesReceived / LastReceived count every arrival.
CREATE OR ALTER VIEW rpt.DQFileStatus AS
SELECT f.FileName, f.SourceType, f.Status, f.RowsRead, f.RowsLoaded, f.RowsRejected, f.LoadRunId, f.LoadTimestamp,
       f.TimesReceived, f.LastReceived
FROM (SELECT fc.*,
             ROW_NUMBER() OVER (PARTITION BY fc.FileName
                                ORDER BY CASE WHEN fc.Status = 'Duplicate' THEN 1 ELSE 0 END, fc.FileControlId DESC) AS rn,
             COUNT(*) OVER (PARTITION BY fc.FileName) AS TimesReceived,
             MAX(fc.LoadTimestamp) OVER (PARTITION BY fc.FileName) AS LastReceived
      FROM audit.Audit_FileControl AS fc) AS f
WHERE f.rn = 1;
GO

-- Grain: one row per distinct data-quality issue, with its lifecycle.
CREATE OR ALTER VIEW rpt.DQIssue AS
SELECT EntityType, NaturalKey, RuleViolated, SourceFile, RawValue, ActionTaken, IssueStatus, FirstSeenUtc, LastSeenUtc,
       RunsSeen, AgeDays, Dimension, RootCauseCategory, RemediationHint, PlantedIssue, OwnerName
FROM audit.vw_DQIssue;
GO

-- Grain: one row per DQ run per entity per outcome - how many checked rows were accepted, and why the others
-- did not pass. Each row gets ONE outcome, its root cause first:
--   Bad record      a rule on the row itself rejected it
--   Duplicate file  the whole file was a re-delivery of one already loaded
--   Parent rejected the row's match was rejected, so it has nothing to attach to (RootCauseCategory 'Upstream dependency')
--   Held: match incomplete  the match is incomplete, so its whole ball-by-ball is held back (rule match_ballbyball_held)
--   Flagged         loaded, with a warning (Flagged or Defaulted rules only)
--   Accepted        no exception
-- IsCurrent = 1 marks the rows that make up today's state: every run for file data (each file is checked once),
-- only the latest run for master data (config.DQEntity.IsFileBased = 0 is re-checked in full on every run).
CREATE OR ALTER VIEW rpt.DQRowOutcome AS
WITH flagged AS (
    SELECT x.LoadRunId, x.EntityType, x.StgRowId,
           MIN(CASE WHEN x.ActionTaken <> 'Rejected' THEN 5
                    WHEN x.RuleViolated = 'match_ballbyball_held' THEN 4
                    WHEN r.RootCauseCategory = 'Upstream dependency' THEN 3
                    WHEN x.RuleViolated = 'duplicate_file' THEN 2
                    ELSE 1 END) AS OutcomeOrder
    FROM audit.Audit_DQException AS x
    LEFT JOIN config.DQRule AS r ON r.RuleId = x.RuleId
    WHERE x.StgRowId IS NOT NULL
    GROUP BY x.LoadRunId, x.EntityType, x.StgRowId
),
counted AS (
    SELECT LoadRunId, EntityType, OutcomeOrder, COUNT(*) AS Rows_ FROM flagged GROUP BY LoadRunId, EntityType, OutcomeOrder
    UNION ALL
    SELECT e.LoadRunId, e.EntityType, 0,
           e.RowsValid - (SELECT COUNT(*) FROM flagged AS f WHERE f.LoadRunId = e.LoadRunId AND f.EntityType = e.EntityType AND f.OutcomeOrder = 5)
    FROM audit.DQRunEntity AS e
)
SELECT c.LoadRunId, c.EntityType, c.OutcomeOrder,
       CASE c.OutcomeOrder WHEN 0 THEN 'Accepted' WHEN 1 THEN 'Bad record' WHEN 2 THEN 'Duplicate file'
                           WHEN 3 THEN 'Parent rejected' WHEN 4 THEN 'Held: match incomplete'
                           ELSE 'Flagged (loaded with a warning)' END AS Outcome,
       CASE WHEN c.OutcomeOrder IN (0, 5) THEN 1 ELSE 0 END AS Passed,
       c.Rows_ AS Rows,
       CASE WHEN de.IsFileBased = 1 OR c.LoadRunId = (SELECT MAX(e2.LoadRunId) FROM audit.DQRunEntity AS e2 WHERE e2.EntityType = c.EntityType)
            THEN 1 ELSE 0 END AS IsCurrent
FROM counted AS c
JOIN config.DQEntity AS de ON de.EntityType = c.EntityType
WHERE c.Rows_ > 0;
GO

-- Grain: one row per DQ run per entity per dimension.
CREATE OR ALTER VIEW rpt.DQScoreTrend AS
SELECT LoadRunId, ScoredAtUtc, EntityType, Dimension, RowsChecked, RowsFailed, ScorePct
FROM audit.DQRunScore;
GO

-- Grain: one row per workflow - its most recent finished run (Succeeded, Failed or Abandoned).
-- Workflow 06 exports this view while 06 and 00_orchestrator are still running, so their latest row is always
-- 'Started'; the last finished run is the meaningful status. A workflow that has never finished shows 'Started'.
-- (A crashed run never reaches the export: the next run's pre-flight refuses while anything is stuck.)
CREATE OR ALTER VIEW rpt.LoadStatus AS
SELECT WorkflowName, Status, StartTime, EndTime, RowsIn, RowsOut, RowsRejected, ErrorMessage
FROM (SELECT l.*, ROW_NUMBER() OVER (PARTITION BY l.WorkflowName
                                     ORDER BY CASE WHEN l.Status = 'Started' THEN 1 ELSE 0 END, l.RunLogId DESC) AS rn
      FROM audit.Audit_ETLRunLog AS l) AS x
WHERE x.rn = 1;
GO
