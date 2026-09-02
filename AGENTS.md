# AGENTS.md - DE214 demo project

Guidance for AI coding agents (Cortex Code) working in this dbt project. The
point of this file is **reproducibility**: anyone - human or agent - should be
able to produce the same correct result every time.

## What this project is

A dbt Project on Snowflake that transforms obfuscated TPC-H source data into a
clean analytics layer and publishes a Snowflake **Semantic View** for AI agents and BI tools.

## Environment & connection

- Local Python env: conda env `de214` at `/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin`.
- Snowflake connection: **`default`**; no `-c` flag needed.
- **Never** read or print `profiles.yml`, `~/.dbt/profiles.yml`, or `connections.toml` — may contain secrets.

## Database & schema layout

Database `DE214` with three schemas:
- `RAW`  - obfuscated source tables (loaded by `scripts/00_setup_sources.sql`).
- `DEV`  - local/iterative dbt target.
- `PROD` - CI/CD deploy target.

All models build into the bare target schema (`DEV` or `PROD`). Data zones are **object-name prefixes**, not schemas.

## Naming conventions (data zones)

- `stg_*`  - staging: clean/rename one source, no business logic.
- `mart_*` - marts: business-grain facts and rollups.
- `sv_*`   - Snowflake Semantic Views (materialized via `dbt_semantic_view`).

## Modeling rules

- **Python models use Snowpark DataFrames, declaratively.** Build a DataFrame and
  return it; do not write imperative row loops or raw cursor SQL.
- Python models can only be `table` or `incremental` (never `view`). The SQL
  model (`stg_customers`) is a `view`.
- The incremental model (`mart_order_sales`) filters new partitions with:
  `session.sql(f"select max(order_date) as max_date from {dbt.this}")`. Use
  `--full-refresh` after changing incremental logic.
- Metrics, joins, and synonyms belong in `sv_*` models, not marts. Use the `semantic-view-authoring` skill for any `sv_*` work.

## One-time setup

```bash
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin

# Build obfuscated RAW source tables from TPC-H
$BIN/snow sql -f scripts/00_setup_sources.sql

# Bundle dbt packages (vendors them into the deploy; needed locally too)
cd dbt_project && $BIN/dbt deps --profiles-dir .
```

## How to run

**Local** (default for development — fast, no deploy round-trip):
```bash
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin
cd dbt_project
$BIN/dbt run --target dev
$BIN/dbt test --target dev
# or a single model:
$BIN/dbt run --select <model> --target dev
```
Requires `DBT_PROFILES_DIR=$HOME/.dbt`. Seed `~/.dbt/profiles.yml` once from `dbt_project/profiles.local.example.yml`.

**Native / CI** (deploy the dbt Project object to Snowflake; required for PROD and to test the full deploy pipeline):
```bash
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin
cd dbt_project
$BIN/snow dbt deploy DE214 --source . --database DE214 --schema DEV
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214 --schema DEV DE214 run --target dev
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214 --schema DEV DE214 test --target dev
```

## Hard rules

- If asked to run or deploy dbt, **use the dbt workflow above** - never hand-write
  and run ad-hoc SQL to "simulate" what a model should do.
- Validate changes locally by calling dbt directly (`dbt parse`, then
  `dbt run` / `dbt test --target dev`); the deployed object is validated via
  `snow dbt execute` in CI / prod.
- Deployment is done by Snowflake CLI / repeatable scripts only. Cortex Code is
  used to *develop and review*, not to imperatively push data changes.
- Never add `authenticator`, `password`, or `{{ env_var(...) }}` to
  `dbt_project/profiles.yml` — those fail server-side.
