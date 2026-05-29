# DE214 Demo Runbook - Data Engineering for AI

This runbook ties the demo to the deck and gives you the exact commands and
prompts for a clean, repeatable live demo. The story has **two "aha" moments**:

1. **DE value** - an AI agent fumbles cryptic raw tables; dbt turns them into a
   clean, well-named mart.
2. **Semantic value** - even against the *clean* mart, the agent mis-defines
   "revenue" and can double-count; the **semantic view** governs it correctly.

> Repo root: `de214_demo/`  ·  dbt project: `de214_demo/dbt_project/`
> Snowflake connection: `default` (account DEMO134)
> Database `DE214_DEMO` with schemas `RAW` (sources), `DEV` (local), `PROD` (CI/CD).

---

## 0. Prerequisites (once)

```bash
# Recreate the local toolchain (conda env `de214`) from the repo root
cd de214_demo
conda env create -f environment.yml      # first time only
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin
```

Versions: dbt-core 1.10.15, dbt-snowflake 1.10.7, Snowflake CLI 3.17.1.

## 1. One-time setup

```bash
# From the repo root: build obfuscated RAW source tables from TPC-H
$BIN/snow sql -f scripts/00_setup_sources.sql

# All dbt work happens inside the project subfolder
cd dbt_project

# Resolve dbt packages locally (vendored into the deploy -> no EAI needed)
$BIN/dbt deps --profiles-dir .

# Deploy the dbt project object and build + test in DEV
$BIN/snow dbt deploy DE214_DEMO --source . --database DE214_DEMO --schema DEV
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO run --target dev
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO test --target dev
```

---

## Deck section -> demo mapping

### Data Engineering Overview  /  dbt + Snowpark DataFrames

Show the project structure (under `dbt_project/`) and that **Python and SQL
models coexist**:
- SQL model: `models/staging/stg_customers.sql`
- Snowpark Python models: `models/staging/stg_orders.py`, `stg_lineitems.py`,
  `models/marts/mart_customer_sales.py`
- **Declarative incremental Python**: `models/marts/mart_order_sales.py`

**Incremental highlight (live):**
```bash
# From repo root: add one "new day" of orders
$BIN/snow sql -f scripts/01_simulate_new_orders.sql
# From dbt_project: re-run - only the new partition is processed
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV \
  DE214_DEMO run --select stg_orders stg_lineitems mart_order_sales --target dev
# Watch the log: "OK created ... mart_order_sales [SUCCESS 10 ...]" -> only 10 rows merged
```

### Moment 1 - the agent fumbles raw data (DE value)

In a Cortex Code session pointed at the demo account, ask about the **raw** tables:

> Using the tables in DE214_DEMO.RAW, what is total revenue by customer market segment?

Expected: the agent struggles with cryptic names (`C_MST.c_seg`, `ORD_HDR.o_tot`,
`LN_ITM.l_xprc/l_disc`), guesses joins, and has no idea what "revenue" means.

Then show the dbt transformation that fixes naming: `RAW` -> `stg_*` -> `mart_*`.

### Semantic Layers  /  Moment 2 - clean names still aren't enough (semantic value)

Point Cortex Code at the **clean mart** (no semantic view yet):

> Using DE214_DEMO.DEV.mart_order_sales, what is total net revenue by market segment?

Expected trap: `mart_order_sales` has BOTH `order_total` (header, includes tax)
and `net_revenue` (line-derived). A naive agent may `SUM(order_total)`, or join
`mart_order_sales` to customers/lines and double-count. The "right" answer is not
knowable from column names alone.

Now show the **semantic view** (`models/marts/sv_sales_analytics.sql`) and query it:

```sql
SELECT * FROM SEMANTIC_VIEW(
  DE214_DEMO.DEV.sv_sales_analytics
  METRICS total_revenue, order_count, avg_order_value
  DIMENSIONS market_segment
) ORDER BY total_revenue DESC;
```

It defines the official `total_revenue = SUM(net_revenue)`, the correct join, the
synonyms, and verified queries - so the agent (and BI tools) get the same correct
answer every time. Inspect the persisted metadata:

```sql
DESCRIBE SEMANTIC VIEW DE214_DEMO.DEV.sv_sales_analytics;
```

### Cortex Code - reproducibility

- `AGENTS.md` - project conventions and hard rules that make results repeatable.
- `.cortex/skills/semantic-view-authoring/SKILL.md` - the **novel** skill that
  teaches the agent the Snowflake `CREATE SEMANTIC VIEW` grammar, the
  `dbt_semantic_view` conventions, and this team's metadata standards. Not git/PR;
  not something base models already know.

Demo the skill:
> Use the semantic-view-authoring skill to review @models/marts/sv_sales_analytics.sql

### DevOps - CI/CD with Snowflake CLI

- `.github/workflows/deploy_dbt_project.yaml` - simple, single-stage deploy to
  **PROD** with the Snowflake CLI (OIDC). `dbt deps` runs in the build step so the
  project is self-contained.
- `.github/workflows/pr_review.yaml` - on PRs touching `sv_*` models, runs Cortex
  Code in batch mode (`cortex -p ... --bypass`) with the review skill and posts an
  advisory comment. Deployment stays 100% Snowflake CLI.

---

## Reset between runs

```bash
# From repo root: remove simulated orders + drop DEV models (keeps RAW intact)
$BIN/snow sql -f scripts/99_reset.sql
# then rebuild (from dbt_project):
$BIN/snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO run --target dev
```

Full teardown: `snow sql -q "DROP DATABASE DE214_DEMO;"` then re-run setup.

---

## Files at a glance

| Path | Purpose |
|------|---------|
| `environment.yml` | Recreate the local conda env `de214` |
| `scripts/00_setup_sources.sql` | Build obfuscated RAW tables from TPC-H |
| `scripts/01_simulate_new_orders.sql` | Append a new day for the incremental demo |
| `scripts/99_reset.sql` | Reset demo state |
| `dbt_project/` | The dbt project (models, macros, profiles.yml) |
| `dbt_project/models/staging/stg_customers.sql` | SQL staging model |
| `dbt_project/models/staging/stg_orders.py`, `stg_lineitems.py` | Snowpark staging models |
| `dbt_project/models/marts/mart_order_sales.py` | Incremental Snowpark fact (order grain) |
| `dbt_project/models/marts/mart_customer_sales.py` | Snowpark customer rollup |
| `dbt_project/models/marts/sv_sales_analytics.sql` | Semantic view (metrics/relationships/synonyms/verified queries) |
| `AGENTS.md` | Agent conventions for reproducibility |
| `.cortex/skills/semantic-view-authoring/` | Custom semantic-view authoring/review skill |
| `.github/workflows/` | Deploy (snow CLI) + Cortex Code PR review |
