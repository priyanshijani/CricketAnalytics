# Step 5 · Transform and load the warehouse (Alteryx 05)

> **Intent:** turn validated rows into a star schema that is correct, history-aware and never half-written.

**Files:** `03_Alteryx/workflows/05_transform_load.yxmc`; publish procedure `dw.usp_PublishWarehouse`
(`01_Setup/sql/08_warehouse_load_schema.sql`). Model: [`data_model/`](../data_model/README.md).

![Workflow 05](../images/alteryx_05_transform_load.png)

## What it does

1. **Reads the queue** in `stg.*Valid`: the latest version of each match, its innings and deliveries.
2. **Dimensions:** venues, players, formats; **`Dim_Team` as Type-2**, building a new version when a team's name
   changes between seasons (Delhi Falcons → Delhi Comets) so history stays correct.
3. **Facts derived from ball by ball:** batting and bowling figures (wides are not balls faced; run outs are not
   bowler wickets), over summary, fall of wickets, and partnerships (tracking who is at the crease ball by ball).
4. **Stages everything** in `stg.LoadReady_*`, then calls **`dw.usp_PublishWarehouse`**, which checks the row counts,
   resolves surrogate keys and applies every table **in one transaction**.

## Why this way

- **Alteryx transforms, SQL publishes:** each Alteryx output commits on its own; one stored procedure makes the
  load all-or-nothing, so a failure leaves the warehouse untouched.
- **A corrected match keeps its key:** its row is updated in place and its ball-level facts are replaced as a set,
  which avoids orphans when a correction adds or removes players.
- **Order-safe on the AMP engine:** a Sort sits directly before every order-dependent Multi-Row Formula
  (results verified identical to the E1 engine).

## Evidence

First load: 119 matches, 233 innings, 28,069 balls, 2,046 batting rows, 1,246 bowling rows, 1,839 partnerships;
`Dim_Team` 9 versions. Checked by `06_Tests/sql/check_dw_load.sql`; a re-run with nothing new changes nothing
(`06_Tests/results/2026-10-05_dw_load.md`).
