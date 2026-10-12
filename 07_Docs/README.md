# 07_Docs

All documentation, organised by the assignment's deliverables (section 14 of the brief).

## Documentation (deliverable 4)

| Topic | Document |
|---|---|
| Solution overview | [solution_overview.md](solution_overview.md) |
| Architecture and data flow | [architecture/](architecture/README.md) · production target: [production_architecture.md](production_architecture.md) |
| Data model | [data_model/](data_model/README.md) |
| Business rules | [business_rules.md](business_rules.md) |
| Data-quality approach | [dq_approach.md](dq_approach.md) |
| Security | [security.md](security.md) |
| Performance | [performance.md](performance.md) |
| Deployment and setup | [deployment.md](deployment.md) |
| Assumptions and limitations | [assumptions_limitations.md](assumptions_limitations.md) |
| Full design and requirement traceability | [00_Project_Plan.md](00_Project_Plan.md) |

## How it was built, step by step

Each page: intent, what was built, why, and the evidence.

| # | Step | Assignment section |
|---|---|---|
| 1 | [Database setup](steps/01_database_setup.md) | 4, 5, 12 |
| 2 | [Source data](steps/02_source_data.md) | 3, 6 |
| 3 | [Ingestion (Alteryx 01–03)](steps/03_ingestion.md) | 5, 7 |
| 4 | [Data-quality gate (Alteryx 04, 04b)](steps/04_data_quality.md) | 6, 7 |
| 5 | [Warehouse load (Alteryx 05)](steps/05_warehouse_load.md) | 5, 10 |
| 6 | [Reporting layer and export (rpt + Alteryx 06)](steps/06_reporting_and_export.md) | 5, 8, 11 |
| 7 | [One-click orchestration (Alteryx 00)](steps/07_orchestration.md) | 7, 12, 16 |
| 8 | [Dashboards (Tableau)](steps/08_dashboards.md) | 8, 9 |
| 9 | [Testing and validation](steps/09_testing.md) | 13 |

## Other

- `images/` — screenshots used by these pages (list in [images/README.md](images/README.md)).
- `presentation/` — the PowerPoint deck (deliverable 5).
