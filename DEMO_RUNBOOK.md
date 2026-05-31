# DE214 Demo Runbook - Data Engineering for AI

This runbook ties the demo to the deck and gives you the exact commands and
prompts for a clean, repeatable live demo.

> Repo root: `de214_demo/` · dbt project: `de214_demo/dbt_project/`
> Snowflake connection: `default` (account DEMO134)
> Database `DE214_DEMO` with schemas `RAW` (sources), `DEV` (local), `PROD` (CI/CD).

## 1. Data Engineering

### Slides

Go through slide content.


## 2. dbt Python Models

### Slides

Go through slide content.

### Demo overview

*Note: Start in Snowsight with Workspaces.*

* Brief overview of Workspaces
* Show empty `DEV` and `PROD` database
* Show `RAW` schema and explain challenge
* Brief overview of Cortex Code in Snowsight

### AI Agent analysis 1
In a Cortex Code session pointed at the demo account, ask about the **raw** tables:

> Using only the tables in DE214_DEMO.RAW, what is total revenue by customer market segment? Do not look at any files in this workspace.

Expected: the agent struggles with cryptic names (`C_MST.c_seg`, `ORD_HDR.o_tot`,
`LN_ITM.l_xprc/l_disc`), guesses joins, and has no idea what "revenue" means.

Here's query it gave me:
```sql
SELECT
    c.C_SEG AS MARKET_SEGMENT,
    SUM(l.L_XPRC * (1 - l.L_DISC)) AS TOTAL_REVENUE
FROM DE214_DEMO.RAW.LN_ITM l
JOIN DE214_DEMO.RAW.ORD_HDR o ON l.L_ORD = o.O_K
JOIN DE214_DEMO.RAW.C_MST c ON o.O_CUST = c.C_K
GROUP BY c.C_SEG
ORDER BY TOTAL_REVENUE DESC
```

| MARKET_SEGMENT | TOTAL_REVENUE |
| --- | --- |
| BUILDING | 44,141,243,552.35 |
| HOUSEHOLD | 43,645,871,354.68 |
| FURNITURE | 43,570,497,982.24 |
| MACHINERY | 43,462,016,360.30 |
| AUTOMOBILE | 43,282,594,635.42 |

### Project walkthrough

*Note: Start in Snowsight with Workspaces.*

* Walkthrough the project structure (under `dbt_project/`)
   * Highlight that **Python and SQL models coexist**
   * Macros and aligning dbt with your zones
* Run dbt compile and view the DAG (deps first if needed)
   * Controls
   * Column level lineage!
* Run the entire dbt project
* Show database objects


### AI Agent analysis 2
Point Cortex Code at the **clean mart** (no semantic view yet):

> Using only the tables in DE214_DEMO.DEV, what is total net revenue by market segment? Do not look at any files in this workspace, and do not look at any other objects in the database including the semantic view.

Expected trap: `mart_order_sales` has BOTH `order_total` (header, includes tax)
and `net_revenue` (line-derived). A naive agent may `SUM(order_total)`, or join
`mart_order_sales` to customers/lines and double-count. The "right" answer is not
knowable from column names alone.

```sql
SELECT MARKET_SEGMENT, SUM(NET_REVENUE) AS TOTAL_NET_REVENUE
FROM DE214_DEMO.DEV.MART_ORDER_SALES o
JOIN DE214_DEMO.DEV.STG_CUSTOMERS c ON o.CUSTOMER_ID = c.CUSTOMER_ID
GROUP BY MARKET_SEGMENT
ORDER BY TOTAL_NET_REVENUE DESC
```

Got same revenue :(

### Incremental Python Pipelines

First add new orders records:

```bash
# From repo root: add one "new day" of orders
$BIN/snow sql -f scripts/01_simulate_new_orders.sql
```

Then run the dbt models with either of these commands:

```bash
dbt run --select stg_orders stg_lineitems mart_order_sales --target dev

# or

snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO \
  run --select stg_orders stg_lineitems mart_order_sales --target dev

# Watch the log: "OK created ... mart_order_sales [SUCCESS 10 ...]" -> only 10 rows merged
```


## 3. Semantic Layers

The story has **two "aha" moments**:

1. **DE value** - an AI agent fumbles cryptic raw tables; dbt turns them into a
   clean, well-named mart.
2. **Semantic value** - even against the *clean* mart, the agent mis-defines
   "revenue" and can double-count; the **semantic view** governs it correctly.

### Moment 1 - the agent fumbles raw data (DE value)

Then show the dbt transformation that fixes naming: `RAW` -> `stg_*` -> `mart_*`.

### Moment 2 - clean names still aren't enough (semantic value)


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


## 4. Cortex Code

### Review AGENTS.md and custom Skill

- `AGENTS.md` - project conventions and hard rules that make results repeatable.
- `.cortex/skills/semantic-view-authoring/SKILL.md` - the skill that teaches the agent the Snowflake `CREATE SEMANTIC VIEW` grammar, the `dbt_semantic_view` conventions, and this team's metadata standards. Not something base models already know.

### Create new semantic view using the skill

Here's the prompt to use:

> Use the semantic-view-authoring skill to create a new semantic view at 'dbt_project/models/marts/sv_customer_analytics.sql' over 'mart_customer_sales' at customer grain. It should answer questions like "who are the top customers by revenue" and "revenue and customer counts by market segment, nation, and region." Follow the team's metadata standards, then run the skill's validation workflow.

Then run/deploy the new dbt model with either of these commands:

```bash
dbt run --select sv_customer_analytics --target dev

# or

snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO \
  run --select sv_customer_analytics --target dev
```

## 5. DevOps

### Overview

- `.github/workflows/deploy_dbt_project.yaml` - simple, single-stage deploy to
  **PROD** with the Snowflake CLI (OIDC). `dbt deps` runs in the build step so the
  project is self-contained.
- `.github/workflows/pr_review.yaml` - on PRs touching `sv_*` models, runs Cortex
  Code in batch mode (`cortex -p ... --bypass`) with the review skill and posts an
  advisory comment. Deployment stays 100% Snowflake CLI.

### Create PR and deploy new semantic view

TODO: Add details here


## 6. Appendix
### Reset between runs

```bash
# From repo root: remove simulated orders + drop DEV models (keeps RAW intact)
snow sql -f scripts/99_reset.sql
```

Full teardown: `snow sql -q "DROP DATABASE DE214_DEMO;"` then re-run setup.


### One-time setup

First create the conda environment with:

```bash
# Recreate the local toolchain (conda env `de214`) from the repo root
cd de214_demo
conda env create -f environment.yml      # first time only
BIN=/opt/homebrew/Caskroom/miniconda/base/envs/de214/bin
```

Then install the Cortex Code CLI with:

```bash
curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh
```

Finally, set up the demo environment in Snowflake with:

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
