# 03_Alteryx/reporting_views

`rpt_reporting_views.sql` builds the `rpt` schema in `CricketDW`: the reporting layer. Kept next to the Alteryx
workflows rather than with the rest of the SQL setup, because workflow `06_export_reporting` reads these
views - they are the contract between the warehouse and the export step, not general-purpose schema.
`01_Setup/setup_database.bat` applies it after the DDL.

- **Business rules** (batting average, strike rate, economy, bowling average, win percentage, match phase,
  home match, impact points) are functions (`rpt.fn_*`) defined once at the top of the script; every view
  calls them. Definitions: `07_Docs/business_rules.md`.
- **22 views**, each stating its grain: match, team × match, team × season, over progression, fall of wicket,
  partnership, batting / bowling innings, player × match, player × season, player career, player × phase,
  rankings, season history, player attributes, points table, season list, and five data-quality / load-status
  views.
- Workflow `06` exports each view `rpt.<Name>` to `04_Prepared/rpt_<Name>.csv` for Tableau.
- The reporting login (`cricket_rpt_reader`) has `SELECT` and `EXECUTE` on this schema only, never on the base
  tables (`07_Docs/security.md`).
- Tests: `06_Tests/sql/check_rpt_views.sql`.
