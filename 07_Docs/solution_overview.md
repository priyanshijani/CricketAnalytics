# Solution Overview

## The problem

A sports analytics organisation holds cricket data in three places: a SQL Server system of record (teams,
players, venues), match files from an external provider (nested JSON) and detailed feeds (CSV: ball by ball,
rankings, history). Nobody can answer "how is my team doing, who is performing, what is changing" without stitching
them together by hand, and nobody can say how much of the data can be trusted.

## The solution in one line

**Alteryx** ingests and validates all three sources into a **SQL Server** star schema, business rules are defined
once in reporting views, and **Tableau** turns them into eight decision-oriented dashboards. One click re-runs
everything when new or corrected data arrives.

## How it works

| Step | Tool | What happens |
|---|---|---|
| 1. Ingest | Alteryx `01`–`03` | SQL master data read live; every JSON / CSV file fingerprinted by content hash (new, changed, duplicate, broken) |
| 2. Validate | Alteryx `04`, `04b` | 43 data-quality rules (stored as data) run inside SQL Server; every violation logged to the row and rule; a quality score per run and a report per data owner |
| 3. Model | Alteryx `05`, SQL | Kimball star schema: Type-2 team history, derived ball-level facts, one-transaction publish |
| 4. Define | SQL `rpt` views | Batting average, strike rate, economy, win % and more, defined exactly once |
| 5. Serve | Alteryx `06` | Every view exported as a Tableau extract, with a manifest of row counts and run ID |
| 6. Decide | Tableau | Insight sentences computed from the data, benchmarks, significance tests, drill-through between pages |

## What a business user gets

| Question | Where |
|---|---|
| Who leads the table, who wins most, how teams trend by season | Leaderboard, Overview, Team |
| Who performs consistently, who adds most value, who is improving | Player leaderboards, Player profile |
| How a team does against each opponent and at each venue | Team |
| How a match unfolded, its turning points and scorecards | Match centre |
| Does the toss matter, are games getting closer, how scoring changes | Trends |
| Can the numbers be trusted | Data Quality |

## What makes it reliable

- **Nothing is silently dropped:** every rejected row has a rule, a reason and an owner.
- **Nothing is half-loaded:** a match is accepted whole or held; the warehouse publishes in one transaction.
- **Nothing is hand-prepared:** new data → one orchestrator run → reopen the workbook.
- **Everything is traceable:** one run ID ties a source file to its exceptions, warehouse rows and exported extract.
- **Everything is tested:** 108 SQL checks map every requirement to evidence (`06_Tests/traceability_matrix.md`).
