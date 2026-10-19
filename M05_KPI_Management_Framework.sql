-- =====================================================================
-- SECTION 6 - KPI RESULTS VIEW
-- Converts the stored KPI snapshot into a standardized KPI code/value
-- structure, allowing multiple KPIs to be queried in a consistent format.
-- Each KPI is returned as one row with its code and numeric value.
-- =====================================================================

CREATE OR REPLACE VIEW vw_kpi_results AS

-- Total number of orders in the snapshot.
SELECT 'TOTAL_ORDERS' AS kpi_code,
       CAST(total_orders AS DECIMAL(20,4)) AS kpi_value
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Total number of delivered orders.
SELECT 'DELIVERED_ORDERS',
       CAST(delivered_orders AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Total number of canceled orders.
SELECT 'CANCELED_ORDERS',
       CAST(canceled_orders AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Percentage of orders that were canceled.
SELECT 'CANCELLATION_RATE',
       CAST(cancellation_rate AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Total merchandise value, excluding freight charges.
SELECT 'MERCHANDISE_VALUE',
       CAST(merchandise_value AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Total freight value associated with order items.
SELECT 'FREIGHT_VALUE',
       CAST(freight_value AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Average order value based on the underlying KPI calculation.
SELECT 'AVERAGE_ORDER_VALUE',
       CAST(average_order_value AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Average delivery duration in days.
SELECT 'AVERAGE_DELIVERY_DAYS',
       CAST(average_delivery_days AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Percentage of eligible delivered orders delivered on or before
-- their estimated delivery dates.
SELECT 'ON_TIME_DELIVERY_RATE',
       CAST(on_time_delivery_rate AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Average customer review score.
SELECT 'AVERAGE_REVIEW_SCORE',
       CAST(average_review_score AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1

UNION ALL

-- Total payment value recorded in the payment summary.
SELECT 'TOTAL_PAYMENT_VALUE',
       CAST(total_payment_value AS DECIMAL(20,4))
FROM kpi_summary_snapshot
WHERE snapshot_id = 1;


-- =====================================================================
-- SECTION 7 - BUSINESS-FRIENDLY KPI DASHBOARD VIEW
-- Combines KPI registry definitions with the corresponding stored values.
-- Only active KPIs are included in the dashboard.
-- =====================================================================

CREATE OR REPLACE VIEW vw_kpi_dashboard AS
SELECT
    r.kpi_code,
    r.kpi_name,
    r.kpi_definition,
    r.calculation_formula,
    r.unit_of_measure,
    r.calculation_grain,
    r.business_purpose,
    v.kpi_value
FROM kpi_registry AS r
LEFT JOIN vw_kpi_results AS v
    ON r.kpi_code = v.kpi_code
WHERE r.is_active = 1;


-- =====================================================================
-- SECTION 8 - VALIDATION
-- Validates KPI availability, registry alignment, and snapshot status.
-- =====================================================================

-- TEST 1: Inspect all calculated KPI results.
-- Expected: 11 KPI rows when the snapshot contains one valid record.
SELECT *
FROM vw_kpi_results
ORDER BY kpi_code;

-- TEST 2: Identify active KPIs without calculated results.
-- EXPECTED: zero rows.
SELECT r.kpi_code, r.kpi_name
FROM kpi_registry AS r
LEFT JOIN vw_kpi_results AS v
    ON r.kpi_code = v.kpi_code
WHERE r.is_active = 1
  AND v.kpi_code IS NULL;

-- TEST 3: Identify calculated KPIs without registry definitions.
-- EXPECTED: zero rows.
SELECT v.kpi_code
FROM vw_kpi_results AS v
LEFT JOIN kpi_registry AS r
    ON v.kpi_code = r.kpi_code
WHERE r.kpi_code IS NULL;

-- TEST 4: Compare the number of active KPIs with calculated results.
-- EXPECTED: 11 active KPIs and 11 calculated results.
SELECT
    (SELECT COUNT(*)
     FROM kpi_registry
     WHERE is_active = 1) AS active_kpi_count,
    (SELECT COUNT(*)
     FROM vw_kpi_results) AS calculated_kpi_count;

-- TEST 5: Inspect the business-friendly KPI dashboard.
SELECT *
FROM vw_kpi_dashboard
ORDER BY kpi_code;

-- TEST 6: Check the number of snapshot records and the latest
-- calculation timestamp.
-- EXPECTED: one row with snapshot_id = 1 in the snapshot table.
SELECT
    COUNT(*) AS snapshot_rows,
    MAX(calculated_at) AS last_calculated_at
FROM kpi_summary_snapshot;

-- Compare active KPI definitions, calculated results, and snapshot rows.
SELECT
    (SELECT COUNT(*)
     FROM kpi_registry
     WHERE is_active = 1) AS active_kpis,

    (SELECT COUNT(*)
     FROM vw_kpi_results) AS calculated_kpis,

    (SELECT COUNT(*)
     FROM kpi_summary_snapshot) AS snapshot_rows;
     
     
