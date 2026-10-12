# 04_Prepared

Step 3 output / step 4 input. Each reporting view `rpt.<Name>` is exported by Alteryx workflow
`06_export_reporting` twice, overwritten on every run:

- `rpt_<Name>.hyper` - a Tableau extract (table `"Extract"."Extract"`). This is what the Tableau workbook reads:
  Tableau Public has no database connectors and accepts only extracts, so this folder is the entire interface
  between the warehouse and the dashboards.
- `rpt_<Name>.csv` - the same rows as a plain file (UTF-8, header row), for inspection and any other tool.

The files from the last baseline run are committed, so the workbook opens straight after a clone; running the
pipeline replaces them. Close Tableau before running the pipeline: an open workbook locks the `.hyper` files.

`_manifest.csv` records, for every export, the file name, source view, row count, batch ID (the export's
`LoadRunId`) and generation timestamp — a traceable link between what SQL Server computed and what the
dashboards show. Workflow `06` reconciles each file's row count with its view before writing the manifest.

Column definitions and grains: `07_Docs/business_rules.md` (one section per view). The CSVs are generated
output; regenerate them by running the pipeline.
