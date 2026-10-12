# 05_Tableau/workbook

`CricketAnalytics.twb` - eight dashboards (Overview, Leaderboard 2.0, Team, Player, Player Leaderboards, Match,
Trends, Data Quality) and a 5-point Season Story over 18 data sources, one per `04_Prepared/rpt_<View>.hyper` extract. `gpl_logo.png` is the
logo in the dashboard header; the workbook finds it through a relative path, so keep it next to the workbook.

Open it in Tableau Public 2026.2 or later (File > Open). It needs nothing else: the extracts are found through
paths relative to this folder, and the baseline extracts are committed with the repository. After running the
pipeline, reopen the workbook to see the new data.
