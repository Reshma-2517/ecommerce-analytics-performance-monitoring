-- ============================================================
-- M10: DATA QUALITY, KPI VALIDATION, AND MONITORING TESTS
-- MySQL 8.0+
-- ============================================================
-- Purpose:
-- Validate database objects, source-data integrity, analytical
-- calculations, KPI consistency, monitoring results, and
-- snapshot history.
-- ============================================================


-- ============================================================
-- SECTION 1: DATABASE AND OBJECT INVENTORY
-- ============================================================

USE olist_analytics;

-- 1. Confirm the active database.
SELECT DATABASE() AS current_database;

-- 2. Count physical tables in the database.
SELECT COUNT(*) AS total_tables
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_type = 'BASE TABLE';

-- 3. Count analytical views.
SELECT COUNT(*) AS total_views
FROM information_schema.views
WHERE table_schema = DATABASE();

-- 4. Check the availability of required analytical views.
SELECT table_name
FROM information_schema.views
WHERE table_schema = DATABASE()
  AND table_name IN (
      'vw_order_item_summary',
      'vw_order_payment_summary',
      'vw_order_review_summary',
      'vw_order_summary',
      'vw_order_item_detail',
      'vw_category_performance',
      'vw_kpi_order_metrics',
      'vw_kpi_results',
      'vw_kpi_dashboard'
  )
ORDER BY table_name;

-- 5. Inspect stored procedures.
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = DATABASE()
  AND routine_type = 'PROCEDURE'
ORDER BY routine_name;

-- 6. Inspect available database tables.
SHOW TABLES;


-- ============================================================
-- SECTION 2: CORE DATA INTEGRITY TESTS
-- ============================================================

USE olist_analytics;

-- 7. Check for duplicate order IDs.
-- A positive count indicates that order_id is not unique
-- in the source table.
SELECT COUNT(*) AS duplicate_order_ids
FROM (
    SELECT order_id
    FROM olist_orders_dataset
    GROUP BY order_id
    HAVING COUNT(*) > 1
) AS duplicates;

-- 8. Identify order items without a matching order.
-- These records may indicate referential-integrity issues.
SELECT COUNT(*) AS orphan_order_items
FROM olist_order_items_dataset i
LEFT JOIN olist_orders_dataset o
    ON i.order_id = o.order_id
WHERE o.order_id IS NULL;

-- 9. Identify payments without a matching order.
SELECT COUNT(*) AS orphan_payments
FROM olist_order_payments_dataset p
LEFT JOIN olist_orders_dataset o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

-- 10. Identify missing or invalid review scores.
-- Valid scores are expected to range from 1 to 5.
SELECT COUNT(*) AS invalid_review_scores
FROM olist_order_reviews_dataset
WHERE review_score IS NULL
   OR review_score NOT BETWEEN 1 AND 5;

-- 11. Identify negative item prices.
SELECT COUNT(*) AS negative_item_prices
FROM olist_order_items_dataset
WHERE price < 0;

-- 12. Identify negative freight values.
SELECT COUNT(*) AS negative_freight_values
FROM olist_order_items_dataset
WHERE freight_value < 0;

-- 13. Identify zero or negative payment values.
SELECT COUNT(*) AS nonpositive_payments
FROM olist_order_payments_dataset
WHERE payment_value <= 0;

-- 14. Check for duplicate order-item identifiers.
-- The order_id and order_item_id combination should identify
-- an individual item within an order.
SELECT COUNT(*) AS duplicate_order_item_keys
FROM (
    SELECT order_id, order_item_id
    FROM olist_order_items_dataset
    GROUP BY order_id, order_item_id
    HAVING COUNT(*) > 1
) AS duplicates;

-- 15. Identify orders without corresponding item records.
SELECT COUNT(*) AS orders_without_items
FROM olist_orders_dataset o
LEFT JOIN olist_order_items_dataset i
    ON o.order_id = i.order_id
WHERE i.order_id IS NULL;


-- ============================================================
-- SECTION 3: KPI CALCULATION AND RECONCILIATION TESTS
-- ============================================================

USE olist_analytics;

-- 16. Compare the source order count with KPI metric rows.
-- Interpret the result according to the intended grain of
-- vw_kpi_order_metrics.
SELECT
    (SELECT COUNT(*)
     FROM olist_orders_dataset) AS raw_total_orders,
    (SELECT COUNT(*)
     FROM vw_kpi_order_metrics) AS kpi_metric_rows;

-- 17. Reconcile delivered-order counts between the source
-- table and the analytical order summary.
SELECT
    (SELECT COUNT(*)
     FROM olist_orders_dataset
     WHERE order_status = 'delivered') AS raw_delivered_orders,
    (SELECT COUNT(*)
     FROM vw_order_summary
     WHERE order_status = 'delivered') AS view_delivered_orders;

-- 18. Reconcile merchandise value between the source item
-- table and the analytical item-detail view.
SELECT
    (SELECT ROUND(SUM(price), 2)
     FROM olist_order_items_dataset) AS raw_merchandise_value,
    (SELECT ROUND(SUM(item_price), 2)
     FROM vw_order_item_detail) AS view_merchandise_value;

-- 19. Reconcile freight value between the source item table
-- and the analytical item-detail view.
SELECT
    (SELECT ROUND(SUM(freight_value), 2)
     FROM olist_order_items_dataset) AS raw_freight_value,
    (SELECT ROUND(SUM(item_freight_value), 2)
     FROM vw_order_item_detail) AS view_freight_value;

-- 20. Reconcile payment value between the source payment table
-- and the payment summary view.
SELECT
    (SELECT ROUND(SUM(payment_value), 2)
     FROM olist_order_payments_dataset) AS raw_payment_value,

    (SELECT ROUND(SUM(payment_amount), 2)
     FROM vw_order_payment_summary) AS summary_payment_value;

-- 21. Inspect the distribution of customer review scores.
-- This helps identify the frequency of each rating.
SELECT
    review_score,
    COUNT(*) AS review_count
FROM olist_order_reviews_dataset
GROUP BY review_score
ORDER BY review_score;

-- 22. Check whether the order summary contains one row per order.
-- Duplicate rows can inflate order counts and downstream totals.
SELECT
    COUNT(*) AS summary_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_summary_rows
FROM vw_order_summary;


-- ============================================================
-- SECTION 4: DATA-QUALITY MONITORING VALIDATION
-- ============================================================

USE olist_analytics;

-- 23. Inspect recent data-quality validation runs.
-- Review execution status, issue totals, and quality scores.
SELECT *
FROM dq_validation_runs
ORDER BY run_id DESC
LIMIT 5;

-- 24. Inspect the latest data-quality rule results.
-- Review the number of evaluated and failed rows per rule.
SELECT *
FROM dq_rule_results
ORDER BY run_id DESC
LIMIT 15;


-- ============================================================
-- SECTION 5: BUSINESS ALERT VALIDATION
-- ============================================================

USE olist_analytics;

-- 25. Inspect recent business-alert monitoring runs.
SELECT *
FROM alert_monitoring_runs
ORDER BY run_id DESC
LIMIT 5;

-- 26. Summarize business alerts by rule and severity.
-- This shows the distribution of recorded alerts across
-- the monitoring rules.
SELECT
    rule_code,
    severity,
    COUNT(*) AS alert_count
FROM business_alerts
GROUP BY rule_code, severity
ORDER BY rule_code, severity;


-- ============================================================
-- SECTION 6: KPI SNAPSHOT VALIDATION
-- ============================================================

USE olist_analytics;

-- 27. Inspect historical KPI snapshots.
-- Compare order volume, cancellations, merchandise value,
-- and payment value across recorded snapshots.
SELECT
    snapshot_id,
    calculated_at,
    total_orders,
    delivered_orders,
    canceled_orders,
    merchandise_value,
    total_payment_value
FROM kpi_summary_snapshot
ORDER BY snapshot_id;

-- 28. Summarize the snapshot history.
-- The timestamps establish the period covered by the records.
SELECT
    COUNT(*) AS total_snapshots,
    MIN(calculated_at) AS first_snapshot,
    MAX(calculated_at) AS latest_snapshot
FROM kpi_summary_snapshot;

-- 29. Check snapshot ID uniqueness.
-- The row count and distinct ID count should match if every
-- snapshot has a unique identifier.
SELECT
    COUNT(*) AS snapshot_rows,
    COUNT(DISTINCT snapshot_id) AS distinct_snapshot_ids
FROM kpi_summary_snapshot;


-- ============================================================
-- SECTION 7: FINAL STRUCTURE VALIDATION
-- ============================================================

-- 30. Inspect the business-alert table definition.
-- Review column types, nullability, keys, and table structure.
DESCRIBE business_alerts;

