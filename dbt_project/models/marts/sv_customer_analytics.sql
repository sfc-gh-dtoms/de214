{{ config(materialized='semantic_view') }}

TABLES (
    customers AS {{ ref('mart_customer_sales') }}
        PRIMARY KEY (customer_id)
        WITH SYNONYMS = ('clients', 'accounts', 'buyers', 'customer accounts')
        COMMENT = 'Customer-grain sales fact: one row per customer with lifetime net revenue, order count, and geography.'
)

FACTS (
    customers.net_revenue AS customers.net_revenue
        WITH SYNONYMS = ('net sales amount')
        COMMENT = 'Customer lifetime net revenue: SUM of line-derived extended_price * (1 - discount) across all orders. Pre-aggregated at customer grain.',
    customers.order_total AS customers.order_total
        COMMENT = 'Customer lifetime header total: includes tax. NOT the official revenue metric.',
    customers.order_count AS customers.order_count
        COMMENT = 'Total number of distinct orders placed by this customer.',
    customers.total_quantity AS customers.total_quantity
        COMMENT = 'Total line-item quantity ordered by this customer across all orders.'
)

DIMENSIONS (
    customers.customer_name AS customers.customer_name
        WITH SYNONYMS = ('customer', 'client name', 'account name'),
    customers.market_segment AS customers.market_segment
        WITH SYNONYMS = ('segment', 'customer segment', 'market')
        COMMENT = 'Customer market segment (e.g. AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, MACHINERY).',
    customers.nation AS customers.nation
        WITH SYNONYMS = ('country', 'nation name')
        COMMENT = 'Country where the customer is based.',
    customers.region AS customers.region
        WITH SYNONYMS = ('sales region', 'geo region', 'geography')
        COMMENT = 'Geographic region grouping nations (e.g. EUROPE, AMERICA, ASIA).',
    customers.most_recent_order_date AS customers.most_recent_order_date
        WITH SYNONYMS = ('last order date', 'latest order', 'last purchase date')
        COMMENT = 'Date of the most recently placed order for this customer.'
)

METRICS (
    customers.total_revenue AS SUM(customers.net_revenue)
        WITH SYNONYMS = ('revenue', 'net revenue', 'total sales', 'lifetime revenue', 'total net revenue')
        COMMENT = 'Official customer lifetime net revenue: SUM of pre-aggregated line-derived net revenue (discount applied, tax excluded).',
    customers.customer_count AS COUNT(customers.customer_id)
        WITH SYNONYMS = ('number of customers', 'count of customers', 'customers', 'headcount')
        COMMENT = 'Number of distinct customers in the result set.',
    customers.avg_revenue_per_customer AS SUM(customers.net_revenue) / NULLIF(COUNT(customers.customer_id), 0)
        WITH SYNONYMS = ('average revenue per customer', 'ARPC', 'avg customer revenue', 'average customer value')
        COMMENT = 'Average lifetime net revenue per customer: total_revenue / customer_count.'
)

COMMENT = 'Customer analytics semantic model: lifetime net revenue, customer counts, and average revenue per customer sliced by name, market segment, nation, and region.'

AI_VERIFIED_QUERIES (
    top_customers_by_revenue AS (
        QUESTION 'Who are the top 10 customers by total lifetime revenue?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT customer_name, total_revenue FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue DIMENSIONS customer_name) ORDER BY total_revenue DESC LIMIT 10'
    ),
    revenue_and_customers_by_segment AS (
        QUESTION 'What is total revenue and customer count by market segment?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT market_segment, total_revenue, customer_count FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue, customer_count DIMENSIONS market_segment) ORDER BY total_revenue DESC'
    ),
    revenue_by_nation_and_region AS (
        QUESTION 'What is total revenue and customer count by nation and region?'
        SQL 'SELECT region, nation, total_revenue, customer_count FROM SEMANTIC_VIEW(sv_customer_analytics METRICS total_revenue, customer_count DIMENSIONS region, nation) ORDER BY region, total_revenue DESC'
    )
)
