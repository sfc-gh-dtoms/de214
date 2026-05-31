-- =============================================================================
-- DE214 demo - 99_reset.sql
-- Resets demo state between runs WITHOUT reloading RAW from TPC-H.
--   * removes simulated "new" orders so the incremental demo can be shown again
--   * drops the DEV-built models so a clean `snow dbt execute ... run` rebuilds
--
--   snow sql -f scripts/99_reset.sql
--
-- To fully tear down everything: DROP DATABASE DE214_DEMO; (then re-run 00).
-- =============================================================================

USE ROLE DEMO_ROLE;
USE WAREHOUSE DEMO_WH;

-- Remove simulated new orders (idempotent).
DELETE FROM DE214_DEMO.RAW.LN_ITM  WHERE l_ord >= 9000000000;
DELETE FROM DE214_DEMO.RAW.ORD_HDR WHERE o_k  >= 9000000000;

-- Drop DEV objects
DROP TABLE IF EXISTS DE214_DEMO.DEV.stg_customers;
DROP TABLE IF EXISTS DE214_DEMO.DEV.stg_orders;
DROP TABLE IF EXISTS DE214_DEMO.DEV.stg_lineitems;
DROP TABLE IF EXISTS DE214_DEMO.DEV.mart_order_sales;
DROP TABLE IF EXISTS DE214_DEMO.DEV.mart_customer_sales;
DROP SEMANTIC VIEW IF EXISTS DE214_DEMO.DEV.sv_sales_analytics;
DROP DBT PROJECT IF EXISTS DE214_DEMO.DEV.DE214_DEMO;

-- Drop PROD objects
DROP TABLE IF EXISTS DE214_DEMO.PROD.stg_customers;
DROP TABLE IF EXISTS DE214_DEMO.PROD.stg_orders;
DROP TABLE IF EXISTS DE214_DEMO.PROD.stg_lineitems;
DROP TABLE IF EXISTS DE214_DEMO.PROD.mart_order_sales;
DROP TABLE IF EXISTS DE214_DEMO.PROD.mart_customer_sales;
DROP SEMANTIC VIEW IF EXISTS DE214_DEMO.PROD.sv_sales_analytics;
DROP DBT PROJECT IF EXISTS DE214_DEMO.PROD.DE214_DEMO;
