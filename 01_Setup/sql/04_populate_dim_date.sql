-- Populates dw.Dim_Date with a calendar spine. This is reference data, not sourced from any
-- of the three source types, so it's seeded directly here rather than by an Alteryx workflow.
-- Idempotent: clears and rebuilds the range every run.
-- Range covers every season in the sample dataset (2023-2025) plus a one-year buffer either side,
-- so a corrected or demo-change file dated slightly outside the baseline range still resolves.

USE CricketDW;
GO

DELETE FROM dw.Dim_Date;
GO

DECLARE @StartDate DATE = '2022-01-01';
DECLARE @EndDate DATE = '2026-12-31';

;WITH Tally AS (
    SELECT TOP (DATEDIFF(DAY, @StartDate, @EndDate) + 1)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
Dates AS (
    SELECT DATEADD(DAY, N, @StartDate) AS FullDate FROM Tally
)
INSERT INTO dw.Dim_Date (DateKey, FullDate, [Year], [Quarter], [Month], MonthName, [Day], DayOfWeekName, IsWeekend, Season)
SELECT
    CAST(FORMAT(FullDate, 'yyyyMMdd') AS INT),
    FullDate,
    YEAR(FullDate),
    DATEPART(QUARTER, FullDate),
    MONTH(FullDate),
    DATENAME(MONTH, FullDate),
    DAY(FullDate),
    DATENAME(WEEKDAY, FullDate),
    CASE WHEN DATENAME(WEEKDAY, FullDate) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END,
    -- Season label matches the generator's convention: a cricket season runs Apr-Mar,
    -- labeled by its starting year (e.g. everything from 2023-04-01 to 2024-03-31 is "2023").
    CAST(CASE WHEN MONTH(FullDate) >= 4 THEN YEAR(FullDate) ELSE YEAR(FullDate) - 1 END AS VARCHAR(20))
FROM Dates;
GO
