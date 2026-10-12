# config

Machine-local configuration: the one place a PC's settings live.

- `local.config.example` — the committed template.
- `local.config` — this PC's copy (gitignored). `01_Setup\check_prerequisites.bat` creates it from the template on
  first run; set `SQL_INSTANCE` in it (e.g. `localhost\SQLEXPRESS`).

`setup_database.bat` (databases) and `create_odbc_dsns.bat` (the ODBC data sources Alteryx connects through) both
read it, so the instance is entered once. No other file in this repo holds a machine-specific value.
