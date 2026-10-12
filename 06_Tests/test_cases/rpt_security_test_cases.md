# Reporting layer and security test cases

Under test: the `rpt` reporting layer (`03_Alteryx/reporting_views/rpt_reporting_views.sql`) and the
least-privilege logins (`01_Setup/sql/09_security.sql`). Design: `07_Docs/business_rules.md`,
`07_Docs/security.md`. Start state: the baseline warehouse loaded by `04` → `05`.

| ID | Case | Expected outcome | How to verify |
|---|---|---|---|
| RPT-TC01 | Every view has its stated grain | One row per match (119), per team per match (238), and as many rows as the facts each view is built on | `check_rpt_views.sql` row-count checks |
| RPT-TC02 | Views lose or double-count nothing | Runs, wickets and runs conceded summed from each view equal the warehouse facts; each innings' final cumulative score equals its total | `check_rpt_views.sql` total checks |
| RPT-TC03 | Results are consistent | Every match with a winner has exactly one Won and one Lost team row; wins = matches with a winner (115); ties 4 and no-results 4 team rows | `check_rpt_views.sql` result checks |
| RPT-TC04 | Business-rule edge cases | Strike rate NULL with 0 balls faced; batting average NULL when never dismissed; economy = runs × 6 ÷ legal balls; win % within 0–100; 23 balls ↔ 3.5 overs; only three phases | `check_rpt_views.sql` guard checks |
| RPT-TC05 | Data quality carried into reporting | Held matches have no batting rows; 3 matches flagged incomplete (M0001, M0006, M0008); the abandoned M0061 counts as complete | `check_rpt_views.sql` DQ checks |
| RPT-TC06 | SCD2 in reporting | DEL 2023 rows show "Delhi Falcons"; every DEL season shows the current name "Delhi Comets" in `TeamCurrentName` | `check_rpt_views.sql` SCD2 checks |
| SEC-TC01 | Source reader | Can read `CricketSource.dbo`; cannot change it; cannot reach `CricketDW` | `check_security.sql` |
| SEC-TC02 | ETL writer | Can read and write `stg`, `dw`, `audit`, read `config`, run the publish; cannot change `config.DQRule`, run DDL or reach `CricketSource` | `check_security.sql` |
| SEC-TC03 | Reporting reader | Can read `rpt` views (including views over `audit`); cannot read `dw`, `audit` or `stg` tables, change anything, or reach `CricketSource` | `check_security.sql` |
| SEC-TC04 | Reporting reader sees every view | Every `rpt` view readable | `check_security.sql` final section returns 0 rows |
| SEC-TC05 | No credentials in the repo | No password in any tracked file; `config/local.config` is gitignored | `git grep -i password` shows only variable names; `git check-ignore config/local.config` |
| SEC-TC06 | Pipeline runs under the least-privilege logins | Workflows `01`–`06` succeed with the connections switched to the SQL logins | Not run yet - a deployment step (`07_Docs/security.md`) |
