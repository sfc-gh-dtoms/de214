{{
    config(
        materialized='table'
    )
}}

-- The one SQL model in the project (everything else is Python/Snowpark),
-- included to show SQL and Python models coexist in the same dbt project.
-- Cleans up the cryptic RAW customer master into business-friendly columns
-- and resolves nation/region from the GEO lookup.

with customers as (
    select
        c_k    as customer_id,
        c_nm   as customer_name,
        c_seg  as market_segment,
        c_nat  as nation_id,
        c_abal as account_balance,
        c_ph   as phone
    from {{ source('raw', 'C_MST') }}
),
geo as (
    select
        n_k  as nation_id,
        n_nm as nation,
        r_nm as region
    from {{ source('raw', 'GEO') }}
)
select
    c.customer_id,
    c.customer_name,
    c.market_segment,
    g.nation,
    g.region,
    c.account_balance,
    c.phone
from customers c
left join geo g
    on c.nation_id = g.nation_id
