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
* Walkthrough the project structure (under `dbt_project/`)
   * Highlight that **Python and SQL models coexist**
   * Python models since dbt Core 1.3 (October 2022)
   * Macros and aligning dbt with your zones
* Run dbt deps with EAI (in setup below)
* Run dbt compile and view the DAG (deps first if needed)
* Run the entire dbt project (move on to next item while this is running)
* Show Workspaces dbt features
   * Controls
   * Column level lineage!
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

* Brief overview of Cortex Code in Snowsight
* Start a new Cortex Code session and enter this prompt:

> Using the objects in DE214.DEV, what is total revenue by market segment? Show your SQL.

This should be the result:

```sql
SELECT
    MARKET_SEGMENT,
    SUM(NET_REVENUE) AS TOTAL_REVENUE
FROM DE214.DEV.MART_CUSTOMER_SALES
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

### SV Benefit After

Start a new Cortex Code session and enter this prompt:

> Using the semantic view in DE214.DEV, what is total revenue by market segment? Show your SQL.

This should be the result:

```sql
SELECT *
FROM SEMANTIC_VIEW(
    DE214.DEV.SV_SALES_ANALYTICS
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

1. Creating a new branch.
1. Use this prompt (and Skill) to build new `sv_customer_analytics` SV:

> /semantic-view-authoring Create a new semantic view at 'dbt_project/models/marts/sv_customer_analytics.sql' over 'mart_customer_sales' at customer grain. It should answer questions like "who are the top customers by revenue" and "revenue and customer counts by market segment, nation, and region." Follow the team's metadata standards, then run the skill's validation workflow.

3. Run/deploy the new dbt model with this command: `dbt run --select sv_customer_analytics --target dev`


## 5. DevOps

### Create PR and deploy new semantic view

* Commit new SV to the branch and push to remote
* Walkthrough GitHub Actions workflow in `.github/workflows` (while waiting)
* Merge PR to main
* Walkthrough GitHub Actions workflow in `.github/workflows` (while waiting)
* Show everything deployed to `PROD` in Snowsight/Horizon

TODO: Decide about merging to main (sv file and dbt_project.yml change)


## 6. Appendix
### Reset between runs

1. Drop database objects with `scripts/99_reset.sql`
1. Delete old Cortex Code sessions
1. Update repo (remove `sv_customer_analytics.py` and reset `dbt_project.yml`)
1. Run dbt deps with EAI
1. Open CoCo Desktop, open terminal, `conda activate de214`
1. Login to Snowsight
1. Open GitHub repo

TODO: Add steps to undo changes merged to main (sv file and dbt_project.yml change)

### To run locally

Use these commands to run things locally:

```bash
# To run a script
snow sql -f scripts/99_reset.sql

# To run dbt
dbt run --select sv_customer_analytics --target dev

# To work with dbt via Snowflake CLI
snow dbt deploy DE214 --source . --database DE214 --schema DEV
snow dbt execute --dbt-version "1.10.15" --database DE214 --schema DEV DE214 run --target dev
snow dbt execute --dbt-version "1.10.15" --database DE214 --schema DEV DE214 run --select sv_customer_analytics --target dev
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
snow dbt deploy DE214 --source . --database DE214 --schema DEV
snow dbt execute --dbt-version "1.10.15" --database DE214 --schema DEV DE214 run --target dev
snow dbt execute --dbt-version "1.10.15" --database DE214 --schema DEV DE214 test --target dev
```
