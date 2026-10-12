-- Performance evidence: (1) the pre-aggregated over summary vs computing it from ball-by-ball on the fly,
-- (2) the time to read every rpt view in full (what workflow 06 does on every run).
-- Timings depend on the machine; each query runs 5 times after one warm-up and the average is reported.
-- Results are recorded in 06_Tests/results/ (PERF-TC01, PERF-TC02); this script is not part of the PASS/FAIL runner.
SET NOCOUNT ON;
SET ANSI_WARNINGS OFF;   -- silences "Null value is eliminated by an aggregate" from the views; timing only
USE CricketDW;

DECLARE @t0 DATETIME2, @i INT, @n BIGINT, @ms_live INT = 0, @ms_agg INT = 0;

-- PERF-TC01  runs and wickets per over per innings: from the facts vs from dw.Agg_OverSummary
SELECT @n = COUNT(*) FROM (SELECT MatchKey, InningsNo, OverNo, SUM(RunsOffBat + ExtraRuns) AS r, SUM(CAST(IsWicket AS INT)) AS w
                           FROM dw.Fact_BallByBall GROUP BY MatchKey, InningsNo, OverNo) AS x;   -- warm-up
SET @i = 0;
WHILE @i < 5
BEGIN
    SET @t0 = SYSDATETIME();
    SELECT @n = COUNT(*) FROM (SELECT MatchKey, InningsNo, OverNo, SUM(RunsOffBat + ExtraRuns) AS r, SUM(CAST(IsWicket AS INT)) AS w
                               FROM dw.Fact_BallByBall GROUP BY MatchKey, InningsNo, OverNo) AS x;
    SET @ms_live += DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000;
    SET @t0 = SYSDATETIME();
    SELECT @n = COUNT(*) FROM (SELECT MatchKey, InningsNo, OverNo, RunsInOver, WicketsInOver FROM dw.Agg_OverSummary) AS x;
    SET @ms_agg += DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000;
    SET @i += 1;
END;
SELECT 'Runs per over: live from Fact_BallByBall' AS Query, (SELECT COUNT(*) FROM dw.Fact_BallByBall) AS RowsScanned, @ms_live / 5.0 AS AvgMs
UNION ALL
SELECT 'Runs per over: read Agg_OverSummary', (SELECT COUNT(*) FROM dw.Agg_OverSummary), @ms_agg / 5.0;

-- PERF-TC02  full read of each rpt view (the export workload)
DECLARE @v SYSNAME, @sql NVARCHAR(400), @ms INT, @rows BIGINT;
DECLARE @res TABLE (ViewName SYSNAME, ViewRows BIGINT, AvgMs DECIMAL(9,1));
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('rpt') ORDER BY name;
OPEN c; FETCH NEXT FROM c INTO @v;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'SELECT * INTO #x FROM rpt.' + QUOTENAME(@v) + N'; SELECT @rows = COUNT_BIG(*) FROM #x; DROP TABLE #x;';
    EXEC sys.sp_executesql @sql, N'@rows BIGINT OUTPUT', @rows = @rows OUTPUT;           -- warm-up
    SET @ms = 0; SET @i = 0;
    WHILE @i < 5
    BEGIN
        SET @t0 = SYSDATETIME();
        EXEC sys.sp_executesql @sql, N'@rows BIGINT OUTPUT', @rows = @rows OUTPUT;
        SET @ms += DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000;
        SET @i += 1;
    END;
    INSERT @res VALUES (@v, @rows, @ms / 5.0);
    FETCH NEXT FROM c INTO @v;
END;
CLOSE c; DEALLOCATE c;
SELECT ViewName, ViewRows, AvgMs FROM @res ORDER BY AvgMs DESC;
SELECT SUM(ViewRows) AS TotalRows, SUM(AvgMs) AS TotalMs FROM @res;
