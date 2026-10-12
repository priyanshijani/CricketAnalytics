-- Checks the latest run of workflows 04_dq_validation and 04b_dq_feedback against the expected baseline.
-- Expected values are for a first run against an empty audit log with the baseline sample data staged
-- (see 06_Tests/test_cases/dq_test_cases.md, DQ-TC01).
--
-- To start from a clean state first, run 06_Tests/sql/reset_pipeline_state.sql.

USE CricketDW;
SET NOCOUNT ON;
DECLARE @run VARCHAR(50) = (SELECT MAX(LoadRunId) FROM audit.DQRunEntity);   -- latest 04 run
SELECT @run AS LatestRun;

-- 1. Run log: 04 and 04b both Started then Succeeded.
--    expect 04: RowsIn 30758, RowsOut 29724, RowsRejected 1034
SELECT TOP 4 RunLogId, WorkflowName, Status, RowsIn, RowsOut, RowsRejected
FROM audit.Audit_ETLRunLog ORDER BY RunLogId DESC;

-- 2. Rows checked per entity; RowsIn = RowsValid + RowsRejected.
--    expect Delivery 29092/28069/1023, HistoricalStats 396/395/1, Innings 239/233/6, Match 123/119/4,
--           Player 152/152/0, PlayerRanking 756/756/0
SELECT EntityType, RowsIn, RowsValid, RowsRejected
FROM audit.DQRunEntity WHERE LoadRunId = @run ORDER BY EntityType;

-- 3. File control, one row per file.
--    expect Duplicate JSON 1; New CSV 5 (30244 read / 29220 loaded / 1024 rejected); New JSON 119; Rejected CSV 1;
--    Rejected JSON 3  (129 files)
SELECT Status, SourceType, COUNT(*) AS Files, SUM(RowsRead) AS RowsRead, SUM(RowsLoaded) AS RowsLoaded, SUM(RowsRejected) AS RowsRejected
FROM audit.Audit_FileControl WHERE LoadRunId = @run
GROUP BY Status, SourceType ORDER BY Status, SourceType;

-- 4. Exceptions per rule.  expect 1076 in total, 19 rule/entity combinations (incl. 772 match_ballbyball_held,
--    31 batsman_dismissed_twice)
SELECT EntityType, RuleViolated, ActionTaken, COUNT(*) AS Exceptions
FROM audit.Audit_DQException WHERE LoadRunId = @run
GROUP BY EntityType, RuleViolated, ActionTaken ORDER BY EntityType, RuleViolated;

-- 5. Planted issues: each DQ issue must produce its exception (expect 0 rows = none missing).
WITH expected (PlantedIssue, EntityType, RuleViolated) AS (
    SELECT 'DQ01', 'Player', 'missing_date_of_birth' UNION ALL
    SELECT 'DQ02', 'Player', 'future_date_of_birth' UNION ALL
    SELECT 'DQ03', 'Innings', 'missing_required_field' UNION ALL
    SELECT 'DQ04', 'Innings', 'wickets_exceed_ten' UNION ALL
    SELECT 'DQ05', 'Match', 'orphan_team_reference' UNION ALL
    SELECT 'DQ06', 'Delivery', 'negative_runs' UNION ALL
    SELECT 'DQ07', 'Delivery', 'orphan_player_reference' UNION ALL
    SELECT 'DQ08', 'Match', 'duplicate_file' UNION ALL
    SELECT 'DQ11', 'Match', 'missing_required_field' UNION ALL
    SELECT 'DQ12', 'Match', 'missing_match_identity' UNION ALL
    SELECT 'DQ13', 'File', 'schema_mismatch'
)
SELECT e.PlantedIssue, e.EntityType, e.RuleViolated AS MissingException
FROM expected AS e
WHERE NOT EXISTS (SELECT 1 FROM audit.Audit_DQException AS x
                  WHERE x.LoadRunId = @run AND x.EntityType = e.EntityType AND x.RuleViolated = e.RuleViolated);

-- 6. Valid queue for workflow 05.
--    expect, before 05 runs: 119 / 233 / 28069 / 756 / 395 / 152 / 119
--    after 05 has published, the queue is consumed: all 0 except PlayersValid 152
SELECT 'MatchValid' AS TableName, COUNT(*) AS Rows_ FROM stg.MatchValid
UNION ALL SELECT 'InningsValid', COUNT(*) FROM stg.InningsValid
UNION ALL SELECT 'BallByBallValid', COUNT(*) FROM stg.BallByBallValid
UNION ALL SELECT 'PlayerRankingValid', COUNT(*) FROM stg.PlayerRankingValid
UNION ALL SELECT 'HistoricalStatsValid', COUNT(*) FROM stg.HistoricalStatsValid
UNION ALL SELECT 'PlayersValid', COUNT(*) FROM stg.PlayersValid
UNION ALL SELECT 'MatchCompletenessValid', COUNT(*) FROM stg.MatchCompletenessValid;

-- 7. Rejected rows never reach stg.*Valid or the warehouse (expect 0 rows).
SELECT 'M0013 in MatchValid' AS Leak FROM stg.MatchValid WHERE MatchId = 'M0013'
UNION ALL SELECT 'Held ball-by-ball in BallByBallValid' FROM stg.BallByBallValid b
    WHERE EXISTS (SELECT 1 FROM stg.MatchCompletenessValid c WHERE c.MatchId = b.MatchId AND c.BallByBallStatus = 'Held')
UNION ALL SELECT 'Future DOB in PlayersValid' FROM stg.PlayersValid WHERE DateOfBirth > CAST(GETDATE() AS date)
UNION ALL SELECT 'M0013 in the warehouse' FROM dw.Fact_MatchResult WHERE MatchId = 'M0013'
UNION ALL SELECT 'Held ball-by-ball in the warehouse' FROM dw.Fact_BallByBall b JOIN dw.Fact_MatchResult fm ON fm.MatchKey = b.MatchKey WHERE fm.BallByBallStatus = 'Held';

-- 8. Matches that are not fully complete (from the queue before 05, from the warehouse after it).
--    expect M0001 Complete/Held, M0006 Incomplete/Held, M0008 Incomplete/Held, M0061 Complete/NULL (abandoned)
SELECT 'queue' AS Source, MatchId, InningsStatus, BallByBallStatus FROM stg.MatchCompletenessValid
WHERE ISNULL(InningsStatus, '') <> 'Complete' OR ISNULL(BallByBallStatus, '') <> 'Loaded'
UNION ALL
SELECT 'warehouse', MatchId, InningsStatus, BallByBallStatus FROM dw.Fact_MatchResult
WHERE ISNULL(InningsStatus, '') <> 'Complete' OR ISNULL(BallByBallStatus, '') <> 'Loaded'
ORDER BY Source, MatchId;

-- 9. Quality scores (04b).  expect Overall: Delivery 96.48, HistoricalStats 99.75, Innings 97.49,
--    Match 96.75, Player 100.00, PlayerRanking 100.00
SELECT EntityType, Dimension, RowsChecked, RowsFailed, ScorePct
FROM audit.DQRunScore WHERE LoadRunId = @run AND Dimension = 'Overall' ORDER BY EntityType;

-- 10. Issue lifecycle (04b) by owner.  expect, all Open on a first run:
--     csv_file_provider 1, master_data_steward 6, match_data_provider 14, player_stats_provider 1
--     (ballbyball_provider expected 1054)
SELECT IssueStatus, OwnerCode, COUNT(*) AS Issues
FROM audit.vw_DQIssue GROUP BY IssueStatus, OwnerCode ORDER BY IssueStatus, OwnerCode;
