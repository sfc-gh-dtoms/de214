{{ config(materialized='semantic_view') }}

-- Semantic view over the order-grain fact and the customer dimension.
-- This is the layer that gives an AI agent what clean column names cannot:
-- the OFFICIAL definition of revenue, the correct join, business synonyms,
-- and verified example queries. Note total_revenue is defined as the
-- line-derived net figure - NOT the order_total header (which includes tax).

TABLES (
    orders AS {{ ref('mart_order_sales') }}
        PRIMARY KEY (order_id)
        WITH SYNONYMS = ('sales', 'order sales', 'transactions')
        COMMENT = 'Order-grain sales fact (one row per order).',
    customers AS {{ ref('stg_customers') }}
        PRIMARY KEY (customer_id)
        WITH SYNONYMS = ('accounts', 'clients', 'buyers')
        COMMENT = 'Customer dimension with segment, nation and region.'
)

RELATIONSHIPS (
    orders_to_customers AS
        orders (customer_id) REFERENCES customers (customer_id)
)

FACTS (
    orders.net_revenue AS orders.net_revenue
        WITH SYNONYMS = ('net sales amount')
        COMMENT = 'Line-derived net revenue: extended_price * (1 - discount).',
    orders.order_total AS orders.order_total
        COMMENT = 'TPC-H header price; includes tax. NOT the official revenue metric.',
    orders.gross_revenue AS orders.gross_revenue
        COMMENT = 'Pre-discount extended price.'
)

DIMENSIONS (
    orders.order_date AS orders.order_date
        WITH SYNONYMS = ('order day', 'purchase date', 'transaction date')
        COMMENT = 'Date the order was placed.',
    orders.order_status AS orders.order_status
        WITH SYNONYMS = ('status'),
    orders.order_priority AS orders.order_priority
        WITH SYNONYMS = ('priority'),
    customers.market_segment AS customers.market_segment
        WITH SYNONYMS = ('segment', 'customer segment', 'market')
        COMMENT = 'Customer market segment (e.g. AUTOMOBILE, BUILDING).',
    customers.region AS customers.region
        WITH SYNONYMS = ('sales region', 'geo region', 'geography'),
    customers.nation AS customers.nation
        WITH SYNONYMS = ('country', 'nation name')
)

METRICS (
    orders.total_revenue AS SUM(CASE WHEN orders.order_status = 'F' THEN orders.net_revenue ELSE 0 END)
        WITH SYNONYMS = ('revenue', 'net revenue', 'total sales', 'total net revenue')
        COMMENT = 'Official revenue: line-derived net revenue (net of discount, excludes tax) for FINALIZED orders only (order_status = F). This governance rule is not knowable from the mart columns alone.',
    orders.order_count AS COUNT(orders.order_id)
        WITH SYNONYMS = ('number of orders', 'order volume', 'count of orders'),
    orders.avg_order_value AS SUM(orders.net_revenue) / NULLIF(COUNT(orders.order_id), 0)
        WITH SYNONYMS = ('AOV', 'average order value', 'average basket size'),
    orders.units_sold AS SUM(orders.total_quantity)
        WITH SYNONYMS = ('units', 'quantity sold', 'total quantity'),
    orders.discount_rate AS 1 - (SUM(orders.net_revenue) / NULLIF(SUM(orders.gross_revenue), 0))
        WITH SYNONYMS = ('discount pct', 'discount percentage', 'average discount')
        COMMENT = 'Effective discount rate: 1 - (SUM(net_revenue) / SUM(gross_revenue)). Returns the proportion of gross revenue lost to discounts.'
)

COMMENT = 'Sales analytics semantic model: net revenue, order volume and AOV by segment, region and time.'

AI_VERIFIED_QUERIES (
    revenue_by_segment AS (
        QUESTION 'What is total net revenue by market segment?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW(sv_sales_analytics METRICS total_revenue DIMENSIONS market_segment)'
    ),
    revenue_by_region_year AS (
        QUESTION 'Show net revenue by region and order year'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT region, YEAR(order_date) AS order_year, total_revenue FROM SEMANTIC_VIEW(sv_sales_analytics METRICS total_revenue DIMENSIONS region, order_date) ORDER BY region, order_year'
    )
)
