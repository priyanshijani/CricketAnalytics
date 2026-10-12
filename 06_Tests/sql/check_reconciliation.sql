-- End-to-end reconciliation: source -> staging -> DQ gate -> warehouse -> reporting views -> export.
-- Valid after ANY successful orchestrator run (not only the first): every check is an invariant of the flow.
-- One row per check: Suite, CheckId, CheckName, Expected, Actual, Result. Test cases: RC-xx in
-- 06_Tests/test_cases/sql_quality_test_cases.md.
SET NOCOUNT ON;
USE CricketDW;

DECLARE @r TABLE (CheckId VARCHAR(10), CheckName NVARCHAR(200), Expected BIGINT, Actual BIGINT);

-- RC01-03  Source system -> staging snapshot (workflow 01 copies master data in full)
INSERT @r SELECT 'RC01', N'CricketSource Teams = stg.TeamsSnapshot',
    (SELECT COUNT(*) FROM CricketSource.dbo.Teams), (SELECT COUNT(*) FROM stg.TeamsSnapshot);
INSERT @r SELECT 'RC02', N'CricketSource Players = stg.PlayersSnapshot',
    (SELECT COUNT(*) FROM CricketSource.dbo.Players), (SELECT COUNT(*) FROM stg.PlayersSnapshot);
INSERT @r SELECT 'RC03', N'CricketSource Venues = stg.VenuesSnapshot',
    (SELECT COUNT(*) FROM CricketSource.dbo.Venues), (SELECT COUNT(*) FROM stg.VenuesSnapshot);

-- RC04-06  Staging -> dimensions
INSERT @r SELECT 'RC04', N'Validated players = dw.Dim_Player',
    (SELECT COUNT(*) FROM stg.PlayersValid), (SELECT COUNT(*) FROM dw.Dim_Player);
INSERT @r SELECT 'RC05', N'Venues in staging = dw.Dim_Venue',
    (SELECT COUNT(*) FROM stg.VenuesSnapshot), (SELECT COUNT(*) FROM dw.Dim_Venue);
INSERT @r SELECT 'RC06', N'Teams in staging = current dw.Dim_Team versions',
    (SELECT COUNT(*) FROM stg.TeamsSnapshot), (SELECT COUNT(*) FROM dw.Dim_Team WHERE IsCurrent = 1);

-- RC07  Every staged file has been through the DQ gate (nothing left pending)
INSERT @r SELECT 'RC07', N'Staged files not yet validated', 0, (SELECT COUNT(*) FROM stg.vw_DQPendingFile);

-- RC08  File control balances: rows read = rows loaded + rows rejected, for every validated file
INSERT @r SELECT 'RC08', N'Files where read <> loaded + rejected', 0,
    (SELECT COUNT(*) FROM audit.Audit_FileControl
     WHERE Status IN ('New', 'Rejected') AND RowsRead <> ISNULL(RowsLoaded, 0) + ISNULL(RowsRejected, 0));

-- RC09  DQ gate balances per entity and run: rows in = rows valid + rows rejected
INSERT @r SELECT 'RC09', N'DQ runs where in <> valid + rejected', 0,
    (SELECT COUNT(*) FROM audit.DQRunEntity WHERE RowsIn <> RowsValid + RowsRejected);

-- RC10  Every match in an accepted match file is in the warehouse, or has a recorded match-level exception
INSERT @r SELECT 'RC10', N'Staged matches neither loaded nor explained by an exception', 0,
    (SELECT COUNT(DISTINCT m.MatchIdRaw)
     FROM stg.MatchRaw AS m
     JOIN audit.Audit_FileControl AS f ON f.FileHash = m.SourceFileHash AND f.Status = 'New'
     WHERE m.MatchIdRaw IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dw.Fact_MatchResult AS fm WHERE fm.MatchId = m.MatchIdRaw)
       AND NOT EXISTS (SELECT 1 FROM audit.Audit_DQException AS x WHERE x.EntityType = 'Match' AND x.NaturalKey LIKE m.MatchIdRaw + '%'));

-- RC11  Nothing in the warehouse that never came through staging
INSERT @r SELECT 'RC11', N'Warehouse matches with no staged source row', 0,
    (SELECT COUNT(*) FROM dw.Fact_MatchResult AS fm
     WHERE NOT EXISTS (SELECT 1 FROM stg.MatchRaw AS m WHERE m.MatchIdRaw = fm.MatchId));

-- RC12  Innings scorecards = sum of their ball-by-ball, partnerships, over summary and fall of wickets
WITH b  AS (SELECT MatchKey, InningsNo, SUM(RunsOffBat + ExtraRuns) AS runs, SUM(CAST(IsWicket AS INT)) AS wkts FROM dw.Fact_BallByBall GROUP BY MatchKey, InningsNo),
     pt AS (SELECT MatchKey, InningsNo, SUM(RunsAdded) AS runs FROM dw.Fact_Partnership GROUP BY MatchKey, InningsNo),
     fw AS (SELECT MatchKey, InningsNo, COUNT(*) AS wkts FROM dw.Fact_FallOfWicket GROUP BY MatchKey, InningsNo),
     ov AS (SELECT MatchKey, InningsNo, SUM(RunsInOver) AS runs, SUM(WicketsInOver) AS wkts FROM dw.Agg_OverSummary GROUP BY MatchKey, InningsNo)
INSERT @r SELECT 'RC12', N'Innings not reconciling with ball-by-ball / partnerships / overs / fall of wickets', 0, COUNT(*)
FROM b
JOIN dw.Fact_Innings AS i ON i.MatchKey = b.MatchKey AND i.InningsNo = b.InningsNo
LEFT JOIN pt ON pt.MatchKey = b.MatchKey AND pt.InningsNo = b.InningsNo
LEFT JOIN fw ON fw.MatchKey = b.MatchKey AND fw.InningsNo = b.InningsNo
LEFT JOIN ov ON ov.MatchKey = b.MatchKey AND ov.InningsNo = b.InningsNo
WHERE i.RunsScored <> b.runs OR ISNULL(pt.runs, -1) <> b.runs OR ov.runs <> b.runs
   OR i.WicketsLost <> b.wkts OR ISNULL(fw.wkts, 0) <> b.wkts OR ov.wkts <> b.wkts;

-- RC13  Batting and bowling scorecards add up to the innings
INSERT @r SELECT 'RC13', N'Innings whose bowlers'' runs conceded exceed the innings total', 0,
    (SELECT COUNT(*) FROM dw.Fact_Innings AS i
     WHERE (SELECT SUM(RunsConceded) FROM dw.Fact_BowlingPerformance AS b WHERE b.MatchKey = i.MatchKey AND b.InningsNo = i.InningsNo) > i.RunsScored);
INSERT @r SELECT 'RC14', N'Innings where batters'' runs + extras <> innings total', 0,
    (SELECT COUNT(*) FROM dw.Fact_Innings AS i
     WHERE EXISTS (SELECT 1 FROM dw.Fact_BattingPerformance AS b WHERE b.MatchKey = i.MatchKey AND b.InningsNo = i.InningsNo)
       AND (SELECT SUM(RunsScored) FROM dw.Fact_BattingPerformance AS b WHERE b.MatchKey = i.MatchKey AND b.InningsNo = i.InningsNo)
           + i.ExtrasTotal <> i.RunsScored);

-- RC15  Warehouse -> reporting views (the views add or lose no rows)
INSERT @r SELECT 'RC15', N'rpt.TeamMatch rows = 2 x matches', 2 * (SELECT COUNT(*) FROM dw.Fact_MatchResult), (SELECT COUNT(*) FROM rpt.TeamMatch);
INSERT @r SELECT 'RC16', N'rpt.BattingInnings runs = batting facts runs',
    (SELECT SUM(RunsScored) FROM dw.Fact_BattingPerformance), (SELECT SUM(RunsScored) FROM rpt.BattingInnings);

-- RC18-19  The Data Quality dashboard's row outcomes (rpt.DQRowOutcome) = the DQ gate's own counts
INSERT @r SELECT 'RC18', N'DQ runs whose row outcomes do not add up to rows in / rows rejected', 0,
    (SELECT COUNT(*) FROM audit.DQRunEntity AS e
     WHERE e.RowsIn <> (SELECT ISNULL(SUM(o.Rows), 0) FROM rpt.DQRowOutcome AS o WHERE o.LoadRunId = e.LoadRunId AND o.EntityType = e.EntityType)
        OR e.RowsRejected <> (SELECT ISNULL(SUM(o.Rows), 0) FROM rpt.DQRowOutcome AS o
                              WHERE o.LoadRunId = e.LoadRunId AND o.EntityType = e.EntityType AND o.Passed = 0));
INSERT @r SELECT 'RC19', N'Rows checked (current state) = file-based rows of every run + master data of the latest run',
    (SELECT SUM(e.RowsIn) FROM audit.DQRunEntity AS e JOIN config.DQEntity AS d ON d.EntityType = e.EntityType
     WHERE d.IsFileBased = 1 OR e.LoadRunId = (SELECT MAX(e2.LoadRunId) FROM audit.DQRunEntity AS e2 WHERE e2.EntityType = e.EntityType)),
    (SELECT SUM(Rows) FROM rpt.DQRowOutcome WHERE IsCurrent = 1);

-- RC20  Leaderboard points table: every season has 2 x matches games and as many wins as matches with a winner
INSERT @r SELECT 'RC20', N'Seasons whose points table games / wins differ from the matches', 0,
    (SELECT COUNT(*) FROM (SELECT p.Season, SUM(p.Played) AS played, SUM(p.Won) AS won FROM rpt.PointsTable AS p GROUP BY p.Season) AS x
     WHERE x.played <> 2 * (SELECT COUNT(*) FROM rpt.Match AS m WHERE m.Season = x.Season)
        OR x.won <> (SELECT COUNT(*) FROM rpt.Match AS m WHERE m.Season = x.Season AND m.WinnerCode IS NOT NULL));

-- RC17  Reporting views -> export: rows exported by the last successful workflow 06 = rows in the views now
--       (holds while nothing has changed since that export; re-run the pipeline after changing data)
DECLARE @sql NVARCHAR(MAX) = N'SELECT @n = 0';
SELECT @sql += N' + (SELECT COUNT_BIG(*) FROM rpt.' + QUOTENAME(name) + N')' FROM sys.views WHERE schema_id = SCHEMA_ID('rpt');
DECLARE @viewRows BIGINT;
EXEC sys.sp_executesql @sql, N'@n BIGINT OUTPUT', @n = @viewRows OUTPUT;
INSERT @r SELECT 'RC17', N'Rows exported by the last workflow 06 run = rows in the rpt views', @viewRows,
    (SELECT TOP (1) RowsOut FROM audit.Audit_ETLRunLog WHERE WorkflowName = '06_export_reporting' AND Status = 'Succeeded' ORDER BY RunLogId DESC);

SELECT 'Reconciliation' AS Suite, CheckId, CheckName, Expected, Actual,
       CASE WHEN Expected = Actual THEN 'PASS' ELSE 'FAIL' END AS Result
FROM @r ORDER BY CheckId;
