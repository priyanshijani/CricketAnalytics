-- Creates the two databases used by this project.
-- CricketSource stands in for a pre-existing system holding cricket master/reference data.
-- CricketDW is the analytical warehouse this project builds: staging, dimensions, facts, audit, reporting.
-- Idempotent: safe to re-run against an existing instance.

IF DB_ID(N'CricketSource') IS NULL
BEGIN
    CREATE DATABASE CricketSource;
END
GO

IF DB_ID(N'CricketDW') IS NULL
BEGIN
    CREATE DATABASE CricketDW;
END
GO
