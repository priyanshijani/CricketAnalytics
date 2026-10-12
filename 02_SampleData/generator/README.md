# 02_SampleData/generator

`generate_sample_data.py` produces the entire `../source/` tree: the SQL Server seed script, the JSON
match files, the CSV files, the four `demo_changes/` categories, and the accompanying schema and
data-quality documentation. Re-running it regenerates the baseline dataset from scratch — it is the
single source of truth for what "the sample data" is, rather than hand-edited files drifting from their
own documentation.
