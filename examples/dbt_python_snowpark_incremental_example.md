# dbt Python Incremental Example

Below are the queries that executed in Snowflake as a result of running `dbt run --select mart_order_sales --target dev`. The outline looks like this:

* Check if table already exists
* Create and execute anonymous Python stored procedure
   * Run query to find max order date
   * Write model DataFrame result to a temp table
* Generate and run a MERGE command from temp table to final table
* Clean up


## Step 1: Check if table exists

```sql
show objects in DE214_DEMO.DEV limit 10000
/* {"app": "dbt", "dbt_version": "1.10.15", "profile_name": "de214_demo", "target_name": "dev", "connection_name": "list_DE214_DEMO_DEV"} */;
```

## Step 2: dbt generated anonymous Python stored procedure

```python
# WITH mart_order_sales__dbt_sp AS PROCEDURE ()
# RETURNS STRING
# LANGUAGE PYTHON
# RUNTIME_VERSION = '3.10'
# PACKAGES = ('snowflake-snowpark-python')
# HANDLER = 'main'
# EXECUTE AS CALLER
# AS $$

import sys
sys._xoptions['snowflake_partner_attribution'].append("dbtLabs_dbtPython")

def model(dbt, session):
    """Order-grain sales fact, built incrementally with Snowpark.

    Demonstrates a DECLARATIVE, incremental Python pipeline:
      * line items are aggregated up to one row per order
      * on an incremental run we only process orders with an order_date newer
        than what already exists in the table (merge on order_id)

    Metric-ambiguity note: this clean, well-named mart intentionally exposes BOTH
    `order_total` (the TPC-H header price, which includes tax) and `net_revenue`
    (line-derived: extended_price * (1 - discount)). Which one is "revenue" is a
    business decision the semantic view makes - not something an agent should
    have to guess from column names alone.
    """
    dbt.config(
        materialized="incremental",
        unique_key="order_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
    )

    from snowflake.snowpark import functions as F

    orders = dbt.ref("stg_orders")
    lines = dbt.ref("stg_lineitems")

    line_net = F.col("extended_price") * (F.lit(1) - F.col("discount"))

    line_agg = lines.group_by("order_id").agg(
        F.sum(line_net).alias("net_revenue"),
        F.sum(F.col("extended_price")).alias("gross_revenue"),
        F.sum(line_net * F.col("tax")).alias("total_tax"),
        F.sum(F.col("quantity")).alias("total_quantity"),
        F.count(F.col("line_number")).alias("line_count"),
    )

    order_sales = orders.join(line_agg, on="order_id", how="inner").select(
        F.col("order_id"),
        F.col("customer_id"),
        F.col("order_date"),
        F.col("order_status"),
        F.col("order_priority"),
        F.col("order_total"),
        F.col("net_revenue"),
        F.col("gross_revenue"),
        F.col("total_tax"),
        F.col("total_quantity"),
        F.col("line_count"),
    )

    if dbt.is_incremental:
        max_date = session.sql(
            f"select max(order_date) as max_date from {dbt.this}"
        ).collect()[0]["MAX_DATE"]
        if max_date is not None:
            order_sales = order_sales.filter(F.col("order_date") > F.lit(max_date))

    return order_sales

# This part is user provided model code
# you will need to copy the next section to run the code
# COMMAND ----------
# this part is dbt logic for get ref work, do not modify

def ref(*args, **kwargs):
    refs = {
        "stg_lineitems": "DE214_DEMO.DEV.stg_lineitems",
        "stg_orders": "DE214_DEMO.DEV.stg_orders",
    }
    key = '.'.join(args)
    version = kwargs.get("v") or kwargs.get("version")
    if version:
        key += f".v{version}"
    dbt_load_df_function = kwargs.get("dbt_load_df_function")
    return dbt_load_df_function(refs[key])

def source(*args, dbt_load_df_function):
    sources = {}
    key = '.'.join(args)
    return dbt_load_df_function(sources[key])

config_dict = {}
meta_dict = {}

class config:
    def __init__(self, *args, **kwargs):
        pass

    @staticmethod
    def get(key, default=None):
        return config_dict.get(key, default)

    @staticmethod
    def meta_get(key, default=None):
        return meta_dict.get(key, default)

class this:
    """dbt.this() or dbt.this.identifier"""
    database = "DE214_DEMO"
    schema = "DEV"
    identifier = "mart_order_sales"

    def __repr__(self):
        return 'DE214_DEMO.DEV.mart_order_sales'

class dbtObj:
    def __init__(self, load_df_function) -> None:
        self.source = lambda *args: source(*args, dbt_load_df_function=load_df_function)
        self.ref = lambda *args, **kwargs: ref(*args, **kwargs, dbt_load_df_function=load_df_function)
        self.config = config
        self.this = this()
        self.is_incremental = True

# COMMAND ----------

def materialize(session, df, target_relation):
    # make sure pandas exists
    import importlib.util
    package_name = 'pandas'
    if importlib.util.find_spec(package_name):
        import pandas
        if isinstance(df, pandas.core.frame.DataFrame):
            session.use_database(target_relation.database)
            session.use_schema(target_relation.schema)
            # session.write_pandas does not have overwrite function
            df = session.createDataFrame(df)

    df.write.mode("overwrite").save_as_table(
        'DE214_DEMO.DEV.mart_order_sales__dbt_tmp', table_type='transient'
    )

def main(session):
    dbt = dbtObj(session.table)
    df = model(dbt, session)
    materialize(session, df, dbt.this)
    return "OK"

# $$ CALL mart_order_sales__dbt_sp()
# /* {"app": "dbt", "dbt_version": "1.10.15", "profile_name": "de214_demo", "target_name": "dev", "node_id": "model.de214_demo.mart_order_sales"} */;
```

## Step 2a: Query to find max order date

```sql
select max(order_date) as max_date from DE214_DEMO.DEV.mart_order_sales
```

## Step 2b: The df.write.mode("overwrite").save_as_table()

```sql
CREATE OR REPLACE TRANSIENT TABLE DE214_DEMO.DEV.mart_order_sales__dbt_tmp (
    "ORDER_ID"       BIGINT,
    "CUSTOMER_ID"    BIGINT,
    "ORDER_DATE"     DATE,
    "ORDER_STATUS"   STRING(1),
    "ORDER_PRIORITY" STRING(15),
    "ORDER_TOTAL"    NUMBER(12, 2),
    "NET_REVENUE"    NUMBER(37, 4),
    "GROSS_REVENUE"  NUMBER(24, 2),
    "TOTAL_TAX"      NUMBER(38, 6),
    "TOTAL_QUANTITY" NUMBER(24, 2),
    "LINE_COUNT"     BIGINT NOT NULL
) AS
SELECT *
FROM (
    SELECT
        "ORDER_ID",
        "CUSTOMER_ID",
        "ORDER_DATE",
        "ORDER_STATUS",
        "ORDER_PRIORITY",
        "ORDER_TOTAL",
        "NET_REVENUE",
        "GROSS_REVENUE",
        "TOTAL_TAX",
        "TOTAL_QUANTITY",
        "LINE_COUNT"
    FROM (
        SELECT *
        FROM (
            (
                SELECT *
                FROM DE214_DEMO.DEV.stg_orders
            ) AS SNOWPARK_LEFT
            INNER JOIN (
                SELECT
                    "ORDER_ID",
                    SUM(("EXTENDED_PRICE" * (1 - "DISCOUNT")))          AS "NET_REVENUE",
                    SUM("EXTENDED_PRICE")                               AS "GROSS_REVENUE",
                    SUM((("EXTENDED_PRICE" * (1 - "DISCOUNT")) * "TAX")) AS "TOTAL_TAX",
                    SUM("QUANTITY")                                     AS "TOTAL_QUANTITY",
                    COUNT("LINE_NUMBER")                                AS "LINE_COUNT"
                FROM (
                    SELECT *
                    FROM DE214_DEMO.DEV.stg_lineitems
                )
                GROUP BY "ORDER_ID"
            ) AS SNOWPARK_RIGHT
            USING (order_id)
        )
    )
    WHERE ("ORDER_DATE" > DATE '1998-08-02')
)
```

## Step 3: Upsert

```sql
begin
/* {"app": "dbt", "dbt_version": "1.10.15", "profile_name": "de214_demo", "target_name": "dev", "node_id": "model.de214_demo.mart_order_sales"} */;

MERGE INTO DE214_DEMO.DEV.mart_order_sales AS DBT_INTERNAL_DEST
USING DE214_DEMO.DEV.mart_order_sales__dbt_tmp AS DBT_INTERNAL_SOURCE
    ON (DBT_INTERNAL_SOURCE.order_id = DBT_INTERNAL_DEST.order_id)
WHEN MATCHED THEN UPDATE SET
    "ORDER_ID"       = DBT_INTERNAL_SOURCE."ORDER_ID",
    "CUSTOMER_ID"    = DBT_INTERNAL_SOURCE."CUSTOMER_ID",
    "ORDER_DATE"     = DBT_INTERNAL_SOURCE."ORDER_DATE",
    "ORDER_STATUS"   = DBT_INTERNAL_SOURCE."ORDER_STATUS",
    "ORDER_PRIORITY" = DBT_INTERNAL_SOURCE."ORDER_PRIORITY",
    "ORDER_TOTAL"    = DBT_INTERNAL_SOURCE."ORDER_TOTAL",
    "NET_REVENUE"    = DBT_INTERNAL_SOURCE."NET_REVENUE",
    "GROSS_REVENUE"  = DBT_INTERNAL_SOURCE."GROSS_REVENUE",
    "TOTAL_TAX"      = DBT_INTERNAL_SOURCE."TOTAL_TAX",
    "TOTAL_QUANTITY" = DBT_INTERNAL_SOURCE."TOTAL_QUANTITY",
    "LINE_COUNT"     = DBT_INTERNAL_SOURCE."LINE_COUNT"
WHEN NOT MATCHED THEN INSERT (
    "ORDER_ID",
    "CUSTOMER_ID",
    "ORDER_DATE",
    "ORDER_STATUS",
    "ORDER_PRIORITY",
    "ORDER_TOTAL",
    "NET_REVENUE",
    "GROSS_REVENUE",
    "TOTAL_TAX",
    "TOTAL_QUANTITY",
    "LINE_COUNT"
)
VALUES (
    "ORDER_ID",
    "CUSTOMER_ID",
    "ORDER_DATE",
    "ORDER_STATUS",
    "ORDER_PRIORITY",
    "ORDER_TOTAL",
    "NET_REVENUE",
    "GROSS_REVENUE",
    "TOTAL_TAX",
    "TOTAL_QUANTITY",
    "LINE_COUNT"
)
/* {"app": "dbt", "dbt_version": "1.10.15", "profile_name": "de214_demo", "target_name": "dev", "node_id": "model.de214_demo.mart_order_sales"} */
;

COMMIT
/* {"app": "dbt", "dbt_version": "1.10.15", "profile_name": "de214_demo", "target_name": "dev", "node_id": "model.de214_demo.mart_order_sales"} */;
```

## Step 4: Clean-up

```sql
drop table if exists DE214_DEMO.DEV.mart_order_sales__dbt_tmp cascade
/* {"app": "dbt", "dbt_version": "1.10.15", "profile_name": "de214_demo", "target_name": "dev", "node_id": "model.de214_demo.mart_order_sales"} */
```
