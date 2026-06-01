{{ config(materialized='semantic_view') }}

-- Customer-grain semantic view over mart_customer_sales.
-- Enables top-customer ranking and revenue/headcount analysis by market
-- segment, nation, and region. The single-table design (one row per customer)
-- avoids fan-out; all measures are pre-aggregated to customer grain.
-- net_revenue is the official revenue metric; order_total includes tax and
-- should not be used for revenue analysis.

TABLES (
    customers AS {{ ref('mart_customer_sales') }}
        PRIMARY KEY (customer_id)
        WITH SYNONYMS = ('accounts', 'clients', 'buyers', 'customer base')
        COMMENT = 'Customer-grain sales rollup: one row per customer with lifetime revenue, order counts, and geographic attributes.'
)

FACTS (
    customers.net_revenue AS customers.net_revenue
        WITH SYNONYMS = ('net sales', 'net amount', 'revenue amount')
        COMMENT = 'Lifetime line-derived net revenue per customer: SUM of extended_price * (1 - discount) across all orders.',
    customers.order_total AS customers.order_total
        COMMENT = 'Lifetime TPC-H header price; includes tax. NOT the official revenue metric.',
    customers.order_count AS customers.order_count
        COMMENT = 'Total distinct orders placed by this customer.',
    customers.total_quantity AS customers.total_quantity
        COMMENT = 'Total units ordered across all line items for this customer.'
)

DIMENSIONS (
    customers.customer_name AS customers.customer_name
        WITH SYNONYMS = ('name', 'client name', 'account name', 'customer')
        COMMENT = 'Customer display name.',
    customers.market_segment AS customers.market_segment
        WITH SYNONYMS = ('segment', 'customer segment', 'market', 'industry')
        COMMENT = 'Customer market segment (e.g. AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, MACHINERY).',
    customers.nation AS customers.nation
        WITH SYNONYMS = ('country', 'nation name', 'home country')
        COMMENT = 'Nation (country) the customer belongs to.',
    customers.region AS customers.region
        WITH SYNONYMS = ('sales region', 'geo region', 'geography', 'area')
        COMMENT = 'Geographic region containing the customer''s nation.',
    customers.most_recent_order_date AS customers.most_recent_order_date
        WITH SYNONYMS = ('last order date', 'latest purchase', 'last purchase date')
        COMMENT = 'Date of the customer''s most recent order.'
)

METRICS (
    customers.total_revenue AS SUM(customers.net_revenue)
        WITH SYNONYMS = ('revenue', 'net revenue', 'total sales', 'total net revenue', 'sales')
        COMMENT = 'Total lifetime net revenue: sum of line-derived net revenue (net of discount, excludes tax) across all customers in the result set.',
    customers.customer_count AS COUNT(customers.customer_id)
        WITH SYNONYMS = ('number of customers', 'count of customers', 'customer volume', 'headcount', 'customers')
        COMMENT = 'Number of distinct customers in the result set.',
    customers.avg_revenue_per_customer AS SUM(customers.net_revenue) / NULLIF(COUNT(customers.customer_id), 0)
        WITH SYNONYMS = ('average revenue per customer', 'ARPC', 'average customer value', 'average lifetime value', 'LTV')
        COMMENT = 'Average lifetime net revenue per customer in the result set.'
)

COMMENT = 'Customer analytics: lifetime revenue, order count, and geographic segmentation at customer grain. Use for top-customer ranking and revenue distribution by market segment, nation, and region.'

AI_VERIFIED_QUERIES (
    top_customers_by_revenue AS (
        QUESTION 'Who are the top 10 customers by total net revenue?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT customer_name, total_revenue FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue DIMENSIONS customer_name) ORDER BY total_revenue DESC LIMIT 10'
    ),
    revenue_and_customers_by_segment AS (
        QUESTION 'What is total revenue and number of customers by market segment?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue, customer_count DIMENSIONS market_segment) ORDER BY total_revenue DESC'
    ),
    revenue_by_nation_and_region AS (
        QUESTION 'Show total revenue and customer count by nation and region'
        SQL 'SELECT * FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue, customer_count DIMENSIONS region, nation) ORDER BY region, total_revenue DESC'
    )
)
