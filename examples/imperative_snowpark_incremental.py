"""Imperative Snowpark version of the dbt incremental Python model.

Compare with the dbt model ``mart_order_sales`` which is only ~30 lines of
declarative Python plus four lines of config.
"""

import os

import snowflake.connector
from snowflake.snowpark import Session, functions as F
from snowflake.snowpark.functions import when_matched, when_not_matched

DATABASE = "DE214"
SCHEMA = "DEV"
TARGET = f"{DATABASE}.{SCHEMA}.mart_order_sales"
STAGING = f"{DATABASE}.{SCHEMA}.mart_order_sales__stage"
UNIQUE_KEY = "ORDER_ID"

def target_exists(session):
    return (
        session.sql(
            f"show tables like 'MART_ORDER_SALES' in schema {DATABASE}.{SCHEMA}"
        ).count()
        > 0
    )

def build_order_sales(session, is_incremental):
    """Same logic the dbt model defines inline.

    The ``is_incremental`` guard mirrors the model's ``if dbt.is_incremental:``
    block: on the first run there is no target to compare against, so no filter.
    """
    orders = session.table(f"{DATABASE}.{SCHEMA}.stg_orders")
    lines = session.table(f"{DATABASE}.{SCHEMA}.stg_lineitems")

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

    if is_incremental:
        max_date = session.sql(
            f"select max(order_date) as max_date from {TARGET}"
        ).collect()[0]["MAX_DATE"]
        if max_date is not None:
            order_sales = order_sales.filter(F.col("order_date") > F.lit(max_date))

    return order_sales


def main():
    from snowflake.snowpark.context import get_active_session
    session = get_active_session()

    is_incremental = target_exists(session)
    order_sales = build_order_sales(session, is_incremental)

    # First run: no target yet, so create it directly (no staging / MERGE).
    if not is_incremental:
        order_sales.write.mode("overwrite").save_as_table(TARGET)
        print(f"Created {TARGET} (initial full load).")
        return

    # Incremental run: land the new partition in a staging table (dbt's __dbt_tmp).
    order_sales.write.mode("overwrite").save_as_table(
        STAGING, table_type="transient"
    )

    # MERGE staging -> target on the unique key (dbt's merge strategy).
    # No "update/insert all" shortcut exists, so derive the assignments from
    # the staging schema instead of hand-maintaining a column list.
    source = session.table(STAGING)
    target = session.table(TARGET)
    assignments = {field.name: source[field.name] for field in source.schema.fields}
    result = target.merge(
        source,
        target[UNIQUE_KEY] == source[UNIQUE_KEY],
        [
            when_matched().update(assignments),
            when_not_matched().insert(assignments),
        ],
    )

    # Clean up the staging table (dbt's drop-temp step).
    session.sql(f"drop table if exists {STAGING}").collect()

    print(
        f"Merged into {TARGET}: "
        f"{result.rows_inserted} inserted, {result.rows_updated} updated."
    )

if __name__ == "__main__":
    main()
