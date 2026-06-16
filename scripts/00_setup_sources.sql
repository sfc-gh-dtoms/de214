-- =============================================================================
-- DE214 demo - 00_setup_sources.sql
-- Builds the DE214_DEMO database, its RAW / DEV / PROD schemas, and loads
-- OBFUSCATED source tables from the TPC-H sample data set.
--
-- Run against the demo account:
--   snow sql -f scripts/00_setup_sources.sql
--
-- The RAW tables are intentionally cryptic and metadata-poor. This is what an
-- AI agent "sees" before any modeling or semantic view exists. Note in
-- particular that two different notions of "revenue" live here:
--   * ORD_HDR.o_tot       -> TPC-H O_TOTALPRICE (includes tax)
--   * LN_ITM.l_xprc/l_disc -> line economics for NET revenue = xprc*(1-disc)
-- ...so "total revenue" is genuinely ambiguous until the semantic view defines
-- it, and the customer->order->line join can fan out and double-count.
-- =============================================================================

USE ROLE DEMO_ROLE;
USE WAREHOUSE DEMO_WH;

CREATE DATABASE IF NOT EXISTS DE214_DEMO;

CREATE SCHEMA IF NOT EXISTS DE214_DEMO.RAW;
CREATE SCHEMA IF NOT EXISTS DE214_DEMO.DEV;
CREATE SCHEMA IF NOT EXISTS DE214_DEMO.PROD;

-- ---------------------------------------------------------------------------
-- Customer master  (<- TPC-H CUSTOMER)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DE214_DEMO.RAW.C_MST AS
SELECT
    c_custkey     AS c_k,
    c_name        AS c_nm,
    c_mktsegment  AS c_seg,
    c_nationkey   AS c_nat,
    c_acctbal     AS c_abal,
    c_phone       AS c_ph
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER;

-- ---------------------------------------------------------------------------
-- Order header  (<- TPC-H ORDERS)
-- o_tot = O_TOTALPRICE (note: TPC-H totalprice includes tax)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DE214_DEMO.RAW.ORD_HDR AS
SELECT
    o_orderkey      AS o_k,
    o_custkey       AS o_cust,
    o_orderdate     AS o_dt,
    o_orderstatus   AS o_sts,
    o_totalprice    AS o_tot,
    o_orderpriority AS o_prio
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- ---------------------------------------------------------------------------
-- Order line items  (<- TPC-H LINEITEM)
-- l_xprc = extended price (pre-discount); l_disc, l_tax are fractions.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DE214_DEMO.RAW.LN_ITM AS
SELECT
    l_orderkey      AS l_ord,
    l_linenumber    AS l_ln,
    l_quantity      AS l_qty,
    l_extendedprice AS l_xprc,
    l_discount      AS l_disc,
    l_tax           AS l_tax,
    l_returnflag    AS l_rf,
    l_shipdate      AS l_shipdt
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;

-- ---------------------------------------------------------------------------
-- Geography lookup  (<- TPC-H NATION + REGION), keyed by nation key
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DE214_DEMO.RAW.GEO AS
SELECT
    n.n_nationkey AS n_k,
    n.n_name      AS n_nm,
    r.r_name      AS r_nm
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION n
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION r
    ON n.n_regionkey = r.r_regionkey;

-- ---------------------------------------------------------------------------
-- Quick sanity check
-- ---------------------------------------------------------------------------
SELECT 'C_MST'   AS tbl, COUNT(*) AS row_cnt FROM DE214_DEMO.RAW.C_MST
UNION ALL SELECT 'ORD_HDR', COUNT(*) FROM DE214_DEMO.RAW.ORD_HDR
UNION ALL SELECT 'LN_ITM',  COUNT(*) FROM DE214_DEMO.RAW.LN_ITM
UNION ALL SELECT 'GEO',     COUNT(*) FROM DE214_DEMO.RAW.GEO
ORDER BY tbl;
