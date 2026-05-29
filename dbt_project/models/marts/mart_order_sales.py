def model(dbt, session):
    """Order-grain sales fact, built incrementally with Snowpark.

    Demonstrates a DECLARATIVE, incremental Python pipeline:
      * line items are aggregated up to one row per order
      * on an incremental run we only process orders with an order_date newer
        than what already exists in the table (merge on order_id)

    Metric-ambiguity note: this clean, well-named mart intentionally exposes
    BOTH `order_total` (the TPC-H header price, which includes tax) and
    `net_revenue` (line-derived: extended_price * (1 - discount)). Which one is
    "revenue" is a business decision the semantic view makes - not something an
    agent should have to guess from column names alone.
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
