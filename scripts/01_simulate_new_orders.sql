-- =============================================================================
-- DE214 demo - 01_simulate_new_orders.sql
-- Appends a single "new day" of orders + line items to the RAW tables so the
-- incremental Python model (mart_order_sales) can be shown processing ONLY the
-- new partition on a second run.
--
--   snow sql -f scripts/01_simulate_new_orders.sql
--
-- Re-runnable: it first removes any previously inserted synthetic rows
-- (order keys >= 9000000000) before re-inserting them.
-- The synthetic order date (1998-08-03) is one day after the TPC-H max.
-- =============================================================================

USE ROLE DEMO_ROLE;
USE WAREHOUSE DEMO_WH;

-- Clean up any prior synthetic rows so this script is idempotent.
DELETE FROM DE214_DEMO.RAW.LN_ITM  WHERE l_ord >= 9000000000;
DELETE FROM DE214_DEMO.RAW.ORD_HDR WHERE o_k  >= 9000000000;

-- 10 brand-new orders dated one day past the TPC-H max date.
INSERT INTO DE214_DEMO.RAW.ORD_HDR (o_k, o_cust, o_dt, o_sts, o_tot, o_prio)
SELECT
    9000000000 + seq AS o_k,
    c_k               AS o_cust,
    DATE '1998-08-03' AS o_dt,
    'O'               AS o_sts,
    NULL              AS o_tot,   -- header total left NULL on purpose
    '3-MEDIUM'        AS o_prio
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY c_k) AS seq, c_k
    FROM DE214_DEMO.RAW.C_MST
    LIMIT 10
);

-- 2 line items per new order.
INSERT INTO DE214_DEMO.RAW.LN_ITM (l_ord, l_ln, l_qty, l_xprc, l_disc, l_tax, l_rf, l_shipdt)
SELECT
    o_k                          AS l_ord,
    ln                           AS l_ln,
    10 * ln                      AS l_qty,
    1000.00 * ln                 AS l_xprc,
    0.05                         AS l_disc,
    0.08                         AS l_tax,
    'N'                          AS l_rf,
    DATE '1998-08-05'            AS l_shipdt
FROM DE214_DEMO.RAW.ORD_HDR
CROSS JOIN (SELECT 1 AS ln UNION ALL SELECT 2) lines
WHERE o_k >= 9000000000;

SELECT COUNT(*) AS new_orders FROM DE214_DEMO.RAW.ORD_HDR WHERE o_k >= 9000000000;
