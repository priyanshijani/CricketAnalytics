# 03_Alteryx

Step 3: ingest, validate, transform, load and export. **Run the whole pipeline by opening
`workflows/00_orchestrator.yxmd` in Designer and pressing Run.**

| Folder / file | Contents |
|---|---|
| `workflows/` | `00_orchestrator.yxmd` (one-click run) and the seven stage macros it runs, `01_ingest_sql.yxmc` … `06_export_reporting.yxmc`, in execution order |
| `macros/` | Shared components: run logging (`Log_ETL_Event`), the data-quality rule engine (`DQ_RunRules`), one CSV reader per feed (`Read_*`), the view exporter (`Export_View`) |
| `reporting_views/` | The `rpt` views and business-rule functions that workflow `06` exports |
| `relink_connections.py` | One-time setup on a new PC: points every workflow at that PC's two Alteryx connections (`07_Docs/deployment.md`, B7). Run with Designer closed; the 11 files it rewrites show as changed in `git status` - expected, do not commit them |

What each stage does and why: `07_Docs/steps/03_ingestion.md` to `07_orchestration.md`.
