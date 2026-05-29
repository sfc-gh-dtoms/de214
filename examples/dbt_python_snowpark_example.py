# WITH anonymous_procedure__dbt_sp AS PROCEDURE ()
# RETURNS STRING
# LANGUAGE PYTHON
# RUNTIME_VERSION = '3.9'
# PACKAGES = ('snowflake-snowpark-python')
# HANDLER = 'main'
# EXECUTE AS CALLER
# AS $$

from snowflake.snowpark.functions import (
    col,
    concat,
    coalesce,
    count,
    lit,
    sum as sum_,
)

def model(dbt, session):
    """
    This model demonstrates basic Snowpark transformations using dbt Python models.

    It joins location data with trucks and aggregates metrics by location.
    Uses raw_pos models as sources instead of tb_101 directly.
    """
    locations_df = dbt.ref("raw_pos_location")
    trucks_df = dbt.ref("raw_pos_truck")
    orders_df = dbt.ref("raw_pos_order_header")

    location_trucks = (
        trucks_df.join(
            locations_df,
            trucks_df["PRIMARY_CITY"] == locations_df["CITY"],
            "inner",
        )
        .select(
            locations_df["LOCATION_ID"],
            locations_df["LOCATION"],
            locations_df["CITY"],
            trucks_df["TRUCK_ID"],
        )
        .groupBy("LOCATION_ID", "LOCATION", "CITY")
        .agg(count("TRUCK_ID").alias("TRUCK_COUNT"))
    )

    location_metrics = (
        orders_df.join(locations_df, "LOCATION_ID", "inner")
        .groupBy("LOCATION_ID")
        .agg(
            sum_("ORDER_TOTAL").alias("TOTAL_SALES"),
            sum_("ORDER_AMOUNT").alias("TOTAL_AMOUNT"),
            sum_("ORDER_TAX_AMOUNT").alias("TOTAL_TAX"),
        )
    )

    joined_df = location_trucks.join(location_metrics, "LOCATION_ID", "left")

    final_df = joined_df.select(
        col("LOCATION_ID"),
        col("LOCATION"),
        col("CITY"),
        col("TRUCK_COUNT"),
        coalesce(col("TOTAL_SALES"), lit(0)).alias("TOTAL_SALES"),
        coalesce(col("TOTAL_AMOUNT"), lit(0)).alias("TOTAL_AMOUNT"),
        coalesce(col("TOTAL_TAX"), lit(0)).alias("TOTAL_TAX"),
    )

    final_with_desc = final_df.withColumn(
        "LOCATION_DESCRIPTION",
        concat(
            col("CITY"),
            lit(" (Trucks: "),
            col("TRUCK_COUNT").cast("string"),
            lit(")"),
        ),
    )

    return final_with_desc


# This part is user provided model code
# you will need to copy the next section to run the code
# COMMAND ----------
# this part is dbt logic for get ref work, do not modify


def ref(*args, **kwargs):
    refs = {
        "raw_pos_location": "tasty_bytes_dbt_db.dev.raw_pos_location",
        "raw_pos_order_header": "tasty_bytes_dbt_db.dev.raw_pos_order_header",
        "raw_pos_truck": "tasty_bytes_dbt_db.dev.raw_pos_truck",
    }
    key = ".".join(args)
    version = kwargs.get("v") or kwargs.get("version")
    if version:
        key += f".v{version}"
    dbt_load_df_function = kwargs.get("dbt_load_df_function")
    return dbt_load_df_function(refs[key])


def source(*args, dbt_load_df_function):
    sources = {}
    key = ".".join(args)
    return dbt_load_df_function(sources[key])


config_dict = {}


class config:
    def __init__(self, *args, **kwargs):
        pass

    @staticmethod
    def get(key, default=None):
        return config_dict.get(key, default)


class this:
    """dbt.this() or dbt.this.identifier"""

    database = "tasty_bytes_dbt_db"
    schema = "dev"
    identifier = "sales_metrics_by_location"

    def __repr__(self):
        return "tasty_bytes_dbt_db.dev.sales_metrics_by_location"


class dbtObj:
    def __init__(self, load_df_function) -> None:
        self.source = lambda *args: source(*args, dbt_load_df_function=load_df_function)
        self.ref = lambda *args, **kwargs: ref(
            *args, **kwargs, dbt_load_df_function=load_df_function
        )
        self.config = config
        self.this = this()
        self.is_incremental = False


# COMMAND ----------


def materialize(session, df, target_relation):
    import importlib.util

    package_name = "pandas"
    if importlib.util.find_spec(package_name):
        import pandas

        if isinstance(df, pandas.core.frame.DataFrame):
            session.use_database(target_relation.database)
            session.use_schema(target_relation.schema)
            df = session.createDataFrame(df)

    df.write.mode("overwrite").save_as_table(
        "tasty_bytes_dbt_db.dev.sales_metrics_by_location",
        table_type="transient",
    )


def main(session):
    dbt = dbtObj(session.table)
    df = model(dbt, session)
    materialize(session, df, dbt.this)
    return "OK"

# $$
# CALL anonymous_procedure__dbt_sp();
