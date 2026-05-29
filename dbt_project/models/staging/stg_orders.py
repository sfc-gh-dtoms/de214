def model(dbt, session):
    """Staging: clean the cryptic RAW order header into friendly column names.

    Snowpark DataFrame transformation (declarative). Note we deliberately keep
    `order_total` (TPC-H O_TOTALPRICE, which includes tax) AS-IS - we do NOT
    decide here what 'revenue' means. That business definition belongs in the
    semantic view, not hard-coded in the transformation layer.
    """
    dbt.config(materialized="table")

    from snowflake.snowpark.functions import col

    orders = dbt.source("raw", "ORD_HDR")

    return orders.select(
        col("o_k").alias("order_id"),
        col("o_cust").alias("customer_id"),
        col("o_dt").alias("order_date"),
        col("o_sts").alias("order_status"),
        col("o_tot").alias("order_total"),
        col("o_prio").alias("order_priority"),
    )
