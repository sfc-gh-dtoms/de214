{{ config(materialized='semantic_view') }}

-- Customer-grain semantic view over mart_customer_sales.
-- Defines official net revenue (line-derived, net of discount), customer count,
-- and average revenue per customer with segment, nation, and region dimensions.
-- The trap column order_total (header price including tax) is exposed as a fact
-- but carries a COMMENT marking it as NOT the official revenue metric.

TABLES (
    customers AS {{ ref('mart_customer_sales') }}
        PRIMARY KEY (customer_id)
        WITH SYNONYMS = ('accounts', 'clients', 'buyers', 'customer sales')
        COMMENT = 'Customer-grain sales mart: one row per customer with aggregated net revenue and order counts.'
)

FACTS (
    customers.net_revenue AS customers.net_revenue
        WITH SYNONYMS = ('net sales amount', 'customer net revenue')
        COMMENT = 'Line-derived net revenue: SUM(extended_price * (1 - discount)) across all orders for this customer.',
    customers.order_total AS customers.order_total
        COMMENT = 'Header-level order total; includes tax. NOT the official revenue metric. Use net_revenue instead.'
)

DIMENSIONS (
    customers.customer_name AS customers.customer_name
        WITH SYNONYMS = ('customer', 'client name', 'account name', 'buyer name'),
    customers.market_segment AS customers.market_segment
        WITH SYNONYMS = ('segment', 'customer segment', 'market')
        COMMENT = 'Customer market segment (e.g. AUTOMOBILE, BUILDING, FURNITURE).',
    customers.nation AS customers.nation
        WITH SYNONYMS = ('country', 'nation name'),
    customers.region AS customers.region
        WITH SYNONYMS = ('sales region', 'geo region', 'geography'),
    customers.most_recent_order_date AS customers.most_recent_order_date
        WITH SYNONYMS = ('last order date', 'latest order', 'most recent purchase')
        COMMENT = 'Date of the most recent order placed by this customer.'
)

METRICS (
    customers.total_revenue AS SUM(customers.net_revenue)
        WITH SYNONYMS = ('revenue', 'net revenue', 'total sales', 'total net revenue', 'customer revenue')
        COMMENT = 'Official revenue metric: SUM of line-derived net revenue (excludes tax, net of discount) across all orders for each customer.',
    customers.customer_count AS COUNT(customers.customer_id)
        WITH SYNONYMS = ('number of customers', 'count of customers', 'customer volume', 'headcount'),
    customers.avg_revenue_per_customer AS SUM(customers.net_revenue) / NULLIF(COUNT(customers.customer_id), 0)
        WITH SYNONYMS = ('average revenue per customer', 'average customer value', 'revenue per customer', 'ARPC')
        COMMENT = 'Average net revenue per customer: total_revenue divided by customer_count.'
)

COMMENT = 'Customer analytics semantic view: net revenue, customer counts, and average revenue at customer grain, sliceable by market segment, nation, and region.'

AI_VERIFIED_QUERIES (
    top_customers_by_revenue AS (
        QUESTION 'Who are the top 10 customers by total revenue?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT customer_name, total_revenue FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue DIMENSIONS customer_name) ORDER BY total_revenue DESC LIMIT 10'
    ),
    revenue_and_customers_by_segment AS (
        QUESTION 'What is total revenue and customer count by market segment?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue, customer_count DIMENSIONS market_segment) ORDER BY total_revenue DESC'
    ),
    revenue_by_nation_and_region AS (
        QUESTION 'Show total revenue and customer count by nation and region'
        SQL 'SELECT * FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue, customer_count DIMENSIONS region, nation) ORDER BY region, total_revenue DESC'
    )
)
