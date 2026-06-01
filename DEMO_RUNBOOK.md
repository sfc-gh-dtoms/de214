# DE214 Demo Runbook - Data Engineering for AI

This runbook gives you the exact commands and prompts for a clean, repeatable live demo.


## 1. Data Engineering

### Slides

Go through slide content.


## 2. dbt Python Models

*Note: Use Snowsight/Workspaces for this section.*

### Slides

Go through slide content.

### Project walkthrough

* Brief overview of Workspaces
* Show empty `DEV` and `PROD` database
* Show `RAW` schema and explain challenge
* Brief overview of Cortex Code in Snowsight
* Walkthrough the project structure (under `dbt_project/`)
   * Highlight that **Python and SQL models coexist**
   * Macros and aligning dbt with your zones
* Run dbt deps with EAI
* Run dbt compile and view the DAG (deps first if needed)
   * Controls
   * Column level lineage!
* Run the entire dbt project
* Show database objects

### Incremental Python Pipelines

* Run the `scripts/01_simulate_new_orders.sql` script
* Re-run affected dbt models with `dbt run --select stg_orders stg_lineitems mart_order_sales --target dev`

Then show exactly what happens during this process:

* Start with Query History
* Then open and walkthrough the `examples/dbt_python_snowpark_incremental_example.md` file
* Finally open and walkthrough the imperative equivalent in `examples/imperative_snowpark_incremental.py`


## 3. Semantic Layers

*Note: Use Snowsight/Workspaces for this section.*

### Slides

Go through slide content.

### SV Benefit Before

Start a new Cortex Code session and enter this prompt:

> Using the objects in DE214_DEMO.DEV, what is total revenue by market segment? Show your SQL.

This should be the result:

```sql
SELECT
    MARKET_SEGMENT,
    SUM(NET_REVENUE) AS TOTAL_REVENUE
FROM DE214_DEMO.DEV.MART_CUSTOMER_SALES
GROUP BY MARKET_SEGMENT
ORDER BY TOTAL_REVENUE DESC
```

| MARKET_SEGMENT | TOTAL_NET_REVENUE |
| --- | --- |
| BUILDING | 44,141,243,552.35 |
| HOUSEHOLD | 43,645,871,354.68 |
| FURNITURE | 43,570,497,982.24 |
| MACHINERY | 43,462,016,360.30 |
| AUTOMOBILE | 43,282,594,635.42 |

### Code walkthrough

* Show Semantic View model in dbt
* Update `dbt_project.yml` config and deploy SV with `dbt run --select sv_sales_analytics --target dev`
* Show SV in Horizon Catalog explorer
* Briefly show how to open the SV in Cortex Analyst??
* Show the sample semantic YAMLs in the examples folder??

TODO: Figure out plan for last two questionable steps here

### SV Benefit After

Start a new Cortex Code session and enter this prompt:

> Using the objects in DE214_DEMO.DEV, what is total revenue by market segment? Show your SQL.

This should be the result:

```sql
SELECT *
FROM SEMANTIC_VIEW(
    DE214_DEMO.DEV.SV_SALES_ANALYTICS
    METRICS total_revenue
    DIMENSIONS customers.market_segment
);
```

| MARKET_SEGMENT | TOTAL_REVENUE |
| --- | --- |
| BUILDING | 21,351,370,255.54 |
| HOUSEHOLD | 21,069,582,508.03 |
| MACHINERY | 21,059,327,023.90 |
| FURNITURE | 21,023,038,594.29 |
| AUTOMOBILE | 20,980,245,745.37 |


## 4. Cortex Code

*Note: Use Cortex Desktop for this section.*

### Slides

Go through slide content.

### Code walkthrough

* Introduce Cortex Desktop
* Review AGENTS.md and custom Skill in repo

### Create new semantic view using the skill

**First, start by creating a new branch.**

Then use this prompt (and Skill) to build the Semantic View:

> Use the semantic-view-authoring skill to create a new semantic view at 'dbt_project/models/marts/sv_customer_analytics.sql' over 'mart_customer_sales' at customer grain. It should answer questions like "who are the top customers by revenue" and "revenue and customer counts by market segment, nation, and region." Follow the team's metadata standards, then run the skill's validation workflow.

Finally, run/deploy the new dbt model with either of these commands:

```bash
dbt run --select sv_customer_analytics --target dev

# or

snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO \
  run --select sv_customer_analytics --target dev
```


## 5. DevOps

### Create PR and deploy new semantic view

* Commit new SV to the branch and push to remote
* Walkthrough GitHub Actions workflow in `.github/workflows` (while waiting)
* Merge PR to main
* Walkthrough GitHub Actions workflow in `.github/workflows` (while waiting)
* Show everything deployed to `PROD` in Snowsight/Horizon


## 6. Appendix
### Reset between runs

1. Drop database objects with `scripts/99_reset.sql`
1. Delete old Cortex Code sessions
1. Open CoCo Desktop, open terminal, `conda activate de214`


If running locally:

```bash
# From repo root: remove simulated orders + drop DEV models (keeps RAW intact)
snow sql -f scripts/99_reset.sql

# Or a full teardown with (followed by re-running the setup)
snow sql -q "DROP DATABASE DE214_DEMO;"
```

### One-time setup

First create the conda environment with:

```bash
# Recreate the local toolchain (conda env `de214`) from the repo root
cd de214_demo
conda env create -f environment.yml
```

Then install the Cortex Code CLI with:

```bash
curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh
```

Finally, set up the demo environment in Snowflake with:

```bash
# From the repo root: build obfuscated RAW source tables from TPC-H
snow sql -f scripts/00_setup_sources.sql

# All dbt work happens inside the project subfolder
cd dbt_project

# Resolve dbt packages locally (vendored into the deploy -> no EAI needed)
dbt deps --profiles-dir .

# Deploy the dbt project object and build + test in DEV
snow dbt deploy DE214_DEMO --source . --database DE214_DEMO --schema DEV
snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO run --target dev
snow dbt execute --dbt-version "1.10.15" --database DE214_DEMO --schema DEV DE214_DEMO test --target dev
```
