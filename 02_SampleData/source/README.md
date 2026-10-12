# 02_SampleData/source

The three source systems, as the assignment describes them:

- `sql_server/` — master/reference data (Teams, Players, Venues), living in a real SQL Server database
  (`CricketSource`). `seed_data.sql` is what actually populates it; the two `.md` files document setup
  and schema.
- `json/` — match-level data as delivered by an external provider, one file per match, nested structure.
- `csv/` — ball-by-ball deliveries, player performance rankings, and historical statistics.

**How they link:** every match has an external match ID (embedded in its JSON), teams and players are
referenced by natural keys shared with `CricketSource`, and CSV rows reference the same match ID. See
`DATA_QUALITY_ISSUES.md` for the deliberately broken versions of these links, and `demo_changes/` for the
files held back to simulate new data arriving after the initial build.

**Arrival pattern (as designed):** SQL Server master data is read live on every run. JSON and CSV files
are each named for the entity and date they represent and are picked up by content, not filename — see
`07_Docs/architecture/` for how a file's identity is determined.
