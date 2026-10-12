# 06_Tests

Step 5: validate everything.

- `sql/` — SQL-level validation scripts (reconciliation, business-rule assertions, referential
  integrity).
- `test_cases/` — test case definitions, each mapped to a requirement in the traceability matrix in
  `07_Docs/00_Project_Plan.md`: expected input, expected outcome, how to verify it.
- `results/` — recorded outcomes of each run: pass/fail, actual vs. expected, date run.

Run every SQL check at once: `run_sql_tests.bat` (108 checks; prints the PASS / FAIL tally and writes the full
output to `results/latest_sql_test_run.txt`, which git ignores). Requirement coverage and the latest status of
every requirement: `traceability_matrix.md`.
