def model(dbt, session):
    """Customer-grain sales mart (Snowpark).

    Rolls order-grain sales up to one row per customer and enriches with the
    customer's segment, nation and region. Aggregating to order grain first
    avoids the classic customer -> order -> line fan-out that would
    double-count revenue.
    """
    dbt.config(materialized="table")

    from snowflake.snowpark import functions as F

    order_sales = dbt.ref("mart_order_sales")
    customers = dbt.ref("stg_customers")

    by_customer = order_sales.group_by("customer_id").agg(
        F.sum(F.col("net_revenue")).alias("net_revenue"),
        F.sum(F.col("order_total")).alias("order_total"),
        F.count_distinct(F.col("order_id")).alias("order_count"),
        F.sum(F.col("total_quantity")).alias("total_quantity"),
        F.max(F.col("order_date")).alias("most_recent_order_date"),
    )

    return by_customer.join(customers, on="customer_id", how="left").select(
        F.col("customer_id"),
        F.col("customer_name"),
        F.col("market_segment"),
        F.col("nation"),
        F.col("region"),
        F.col("net_revenue"),
        F.col("order_total"),
        F.col("order_count"),
        F.col("total_quantity"),
        F.col("most_recent_order_date"),
    )
