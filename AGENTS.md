# AGENTS.md - DE214 demo project

Guidance for AI coding agents (Cortex Code) working in this dbt project. The
point of this file is **reproducibility**: anyone - human or agent - should be
able to produce the same correct result every time.

## What this project is

A dbt Project on Snowflake that transforms obfuscated TPC-H source data into a
clean, AI-ready analytics layer, and publishes a Snowflake **Semantic View** for
AI agents and BI tools. Mostly Python (Snowpark) models, one SQL model, one
incremental model, plus semantic views managed as dbt models.

## Environment & connection

- Local Python env (Snowflake CLI + dbt): conda env `de214` at
  `/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin`. Recreate it with
  `conda env create -f environment.yml`.
- Snowflake connection: the **`default`** connection (account DEMO134). It is the
  default, so no `-c` flag is needed: `snow ...`.
- dbt runs **two ways** (see "How to run"): *native* (inside Snowflake via the
  Snowflake CLI) for deploy/CI, and *local* (plain `dbt` from the laptop) for fast
  iteration. The committed `dbt_project/profiles.yml` is the **native** profile;
  local auth lives only in your own `~/.dbt/profiles.yml`.
- **Never** read or print `profiles.yml`, `~/.dbt/profiles.yml`, or
  `connections.toml`; they may contain secrets. The committed `profiles.yml`
  intentionally contains **no** password/authenticator - native auth comes from the
  `snow` connection / executing session.

## Database & schema layout

Database `DE214_DEMO` with three schemas:
- `RAW`  - obfuscated source tables (loaded by `scripts/00_setup_sources.sql`).
- `DEV`  - local/iterative dbt target.
- `PROD` - CI/CD deploy target.

All models build into the bare target schema (`DEV` or `PROD`); see
`macros/generate_schema_name.sql`. Data zones are **object-name prefixes**, not
schemas.

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
- **Keep metrics and relationships OUT of the transformation layer.** Marts may
  carry raw measures (e.g. both `order_total` and `net_revenue`), but the
  *official* definition of a metric, the correct join, synonyms, and verified
  queries belong in the **semantic view** (`models/marts/sv_*.sql`) - not
  hard-coded into a mart. When authoring or editing a semantic view, use the
  `semantic-view-authoring` skill.

## Repository layout

```
de214_demo/                  <- repo root (this file, skill, CI, scripts)
├── AGENTS.md
├── environment.yml          <- recreate the local conda env `de214`
├── DEMO_RUNBOOK.md
├── .cortex/skills/          <- semantic-view-authoring skill
├── .github/workflows/       <- deploy + PR review
├── scripts/                 <- setup / simulate / reset SQL
└── dbt_project/            <- the dbt project (models, macros, profiles.yml)
```

## How to run

```bash
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin

# (once) build obfuscated RAW sources - scripts live at the repo root
$BIN/snow sql -f scripts/00_setup_sources.sql

# all dbt work happens inside the project subfolder
cd dbt_project

# install packages locally so they bundle into the deploy (no EAI needed)
$BIN/dbt deps --profiles-dir .

# deploy the project object, then run + test (dev)
$BIN/snow dbt deploy DE214_DEMO --source . --database DE214_DEMO --schema DEV
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO run --target dev
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO test --target dev
```

### Two ways to run dbt

**Native (deploy / CI / production):** the commands above. The dbt project is
bundled and run *inside* Snowflake; auth comes from the `snow` connection (or the
executing session). Uses the committed `dbt_project/profiles.yml` (no secrets).

**Local (fast iteration):** plain `dbt` from the laptop, hitting `DE214_DEMO.DEV`
directly over SSO. dbt's profile search order is `--profiles-dir` -> **project
root** -> `~/.dbt/`, so the committed `dbt_project/profiles.yml` (no auth) would
otherwise win and fail with `Database Error 251006: Password is empty`. We avoid
that by pointing dbt at `~/.dbt` via a persistent env var:

```bash
# one-time: seed your local profile (or MERGE the de214_demo block if the file exists)
cp dbt_project/profiles.local.example.yml ~/.dbt/profiles.yml

# one-time: make ~/.dbt the default profiles dir for all shells
echo 'export DBT_PROFILES_DIR="$HOME/.dbt"' >> ~/.zshrc   # then restart the shell

# thereafter, from inside dbt_project/, bare commands just work:
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin
cd dbt_project
$BIN/dbt run --target dev
$BIN/dbt build --target dev
```

The global `DBT_PROFILES_DIR` does **not** affect the native/CI commands above:
they pass `--profiles-dir .` explicitly, and the flag overrides the env var, so
deploy still uses the committed `dbt_project/profiles.yml`.

**Hard rule:** never add `authenticator`, `password`, or `{{ env_var(...) }}` to
the committed `dbt_project/profiles.yml` - those fail to deploy server-side; local
auth belongs only in `~/.dbt/profiles.yml`.

## Hard rules

- If asked to run or deploy dbt, **use the dbt workflow above** - never hand-write
  and run ad-hoc SQL to "simulate" what a model should do.
- Validate changes locally by calling dbt directly (`dbt parse`, then
  `dbt run` / `dbt test --target dev`); the deployed object is validated via
  `snow dbt execute` in CI / prod.
- Deployment is done by Snowflake CLI / repeatable scripts only. Cortex Code is
  used to *develop and review*, not to imperatively push data changes.
