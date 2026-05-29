def model(dbt, session):
    """Staging: clean the cryptic RAW line items into friendly column names.

    Snowpark DataFrame transformation (declarative). We surface the raw line
    economics (extended_price, discount, tax) without collapsing them into a
    single 'revenue' number - that definition is the semantic view's job.
    """
    dbt.config(materialized="table")

    from snowflake.snowpark.functions import col

    lineitems = dbt.source("raw", "LN_ITM")

    return lineitems.select(
        col("l_ord").alias("order_id"),
        col("l_ln").alias("line_number"),
        col("l_qty").alias("quantity"),
        col("l_xprc").alias("extended_price"),
        col("l_disc").alias("discount"),
        col("l_tax").alias("tax"),
        col("l_rf").alias("return_flag"),
        col("l_shipdt").alias("ship_date"),
    )
