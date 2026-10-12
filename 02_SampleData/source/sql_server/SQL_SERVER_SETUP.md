# SQL Server Setup

`CricketSource` holds the master/reference data seeded by `seed_data.sql`. Setup is handled entirely by
`01_Setup/setup_database.bat`, which reads the instance name and authentication mode from
`config/local.config`.

## Steps

1. Copy `config/local.config.example` to `config/local.config` and set `SQL_INSTANCE` to your instance
   name (for example `localhost`, `.\SQLEXPRESS`, or a named instance).
2. Run `01_Setup/check_prerequisites.bat` to confirm `sqlcmd` (go-sqlcmd) and the ODBC Driver 17 for
   SQL Server are available.
3. Run `01_Setup/setup_database.bat`. This creates `CricketSource` and `CricketDW`, runs every script in
   `01_Setup/sql/` in order, and seeds `CricketSource` from `seed_data.sql`.

## Verification

```sql
USE CricketSource;
SELECT COUNT(*) AS TeamCount FROM dbo.Teams;      -- expect 8
SELECT COUNT(*) AS VenueCount FROM dbo.Venues;    -- expect 8
SELECT COUNT(*) AS PlayerCount FROM dbo.Players;  -- expect 150ish, see CricketSource_SCHEMA.md
```

## Troubleshooting

- **`sqlcmd` not found**: install go-sqlcmd (`winget install sqlcmd`) and open a new terminal. See
  `07_Docs/deployment.md` Prerequisites.
- **Login failed**: check `SQL_AUTH_MODE` in `config/local.config` matches how your instance is
  configured (Windows Authentication is the default).
