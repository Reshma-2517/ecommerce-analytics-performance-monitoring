-- ============================================================
-- M09: TESTING AND PERFORMANCE OPTIMIZATION
-- MySQL 8.0+
-- ============================================================
-- Objective:
-- Evaluate query execution plans, inspect index coverage,
-- identify expensive analytical operations, and assess
-- opportunities to improve database performance.
--
-- Scope:
-- 1. Database and index inventory
-- 2. Index coverage and access-path analysis
-- 3. Execution-plan testing
-- 4. Actual execution-time analysis
-- 5. Analytical workload optimization
-- 6. Performance review and optimization decisions
-- ============================================================


-- ============================================================
-- SECTION 1: DATABASE AND INDEX INVENTORY
-- ============================================================

USE olist_analytics;

-- 1. Confirm the database context.
SELECT DATABASE() AS current_database;

-- 2. Inspect the storage engines and approximate row counts
-- of the database tables.
-- TABLE_ROWS may be an estimate for InnoDB tables.
SELECT
    table_name,
    engine,
    table_rows,
    data_length,
    index_length,
    ROUND(data_length / 1024 / 1024, 2) AS data_size_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_size_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_type = 'BASE TABLE'
ORDER BY data_length DESC;

-- 3. Inspect indexes on the orders table.
-- Primary and secondary indexes influence how MySQL locates
-- orders and evaluates filters on indexed columns.
SHOW INDEX FROM olist_orders_dataset;

-- 4. Inspect indexes on the order-items table.
-- Indexes can affect order-level item lookups and aggregations.
SHOW INDEX FROM olist_order_items_dataset;

-- 5. Inspect indexes on the payments table.
-- Payment analysis commonly filters and groups records by order_id.
SHOW INDEX FROM olist_order_payments_dataset;

-- 6. Inspect indexes on the reviews table.
-- Review lookups and order-level review joins may benefit
-- from suitable indexes.
SHOW INDEX FROM olist_order_reviews_dataset;

-- 7. Review all indexes on the main source tables.
-- This provides a consolidated view of indexed columns,
-- uniqueness, and index definitions.
SELECT
    table_name,
    index_name,
    non_unique,
    seq_in_index,
    column_name,
    index_type
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name IN (
      'olist_orders_dataset',
      'olist_order_items_dataset',
      'olist_order_payments_dataset',
      'olist_order_reviews_dataset'
  )
ORDER BY table_name, index_name, seq_in_index;


-- ============================================================
-- SECTION 2: INDEX COVERAGE AND ACCESS-PATH ANALYSIS
-- ============================================================

-- 8. Inspect indexes defined on the order identifier.
-- This helps establish whether MySQL has an indexed access path
-- for lookups by order_id.
SELECT
    table_name,
    index_name,
    column_name,
    seq_in_index,
    non_unique
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'olist_orders_dataset'
  AND column_name = 'order_id'
ORDER BY index_name, seq_in_index;

-- 9. Inspect order-item indexes involving order_id.
-- These indexes are relevant to joins and grouping by order.
SELECT
    table_name,
    index_name,
    column_name,
    seq_in_index,
    non_unique
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'olist_order_items_dataset'
  AND column_name = 'order_id'
ORDER BY index_name, seq_in_index;

-- 10. Inspect payment indexes involving order_id.
-- This is relevant to payment-summary queries and order joins.
SELECT
    table_name,
    index_name,
    column_name,
    seq_in_index,
    non_unique
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'olist_order_payments_dataset'
  AND column_name = 'order_id'
ORDER BY index_name, seq_in_index;

-- 11. Inspect indexes involving the purchase timestamp.
-- The results help assess the available index coverage for
-- time-based filtering and monthly reporting.
SELECT
    table_name,
    index_name,
    column_name,
    seq_in_index,
    non_unique
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'olist_orders_dataset'
  AND column_name = 'order_purchase_timestamp'
ORDER BY index_name, seq_in_index;

-- 12. Inspect indexes involving order status.
-- This identifies available index coverage for status-based
-- filters used in operational reporting.
SELECT
    table_name,
    index_name,
    column_name,
    seq_in_index,
    non_unique
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'olist_orders_dataset'
  AND column_name = 'order_status'
ORDER BY index_name, seq_in_index;


-- ============================================================
-- SECTION 3: EXECUTION-PLAN TESTING
-- ============================================================
-- EXPLAIN shows the optimizer's intended execution plan.
-- Review access type, possible_keys, key, rows, and Extra.
-- Estimated rows and costs are not actual execution timings.


-- 13. Inspect a lookup by order ID.
-- This represents a common operational lookup pattern.
EXPLAIN
SELECT *
FROM olist_orders_dataset
WHERE order_id = (
    SELECT order_id
    FROM olist_orders_dataset
    ORDER BY order_purchase_timestamp
    LIMIT 1
);

-- 14. Inspect filtering by order status.
-- This evaluates the access path for a common status filter.
EXPLAIN
SELECT
    order_id,
    order_purchase_timestamp,
    order_status
FROM olist_orders_dataset
WHERE order_status = 'delivered';

-- 15. Inspect filtering by purchase timestamp.
-- This represents a date-range reporting workload.
EXPLAIN
SELECT
    order_id,
    order_purchase_timestamp,
    order_status
FROM olist_orders_dataset
WHERE order_purchase_timestamp >= '2018-01-01'
  AND order_purchase_timestamp < '2018-02-01';

-- 16. Inspect order-item aggregation by order.
-- Grouping may require scanning and aggregating a large
-- number of item records.
EXPLAIN
SELECT
    order_id,
    SUM(price) AS merchandise_value,
    SUM(freight_value) AS freight_value
FROM olist_order_items_dataset
GROUP BY order_id;

-- 17. Inspect payment aggregation by order.
-- This is a common operation for payment reconciliation
-- and order-level financial reporting.
EXPLAIN
SELECT
    order_id,
    SUM(payment_value) AS total_payment_value
FROM olist_order_payments_dataset
GROUP BY order_id;

-- 18. Inspect an order-to-item join.
-- This plan helps assess how MySQL accesses the tables
-- and combines order records with their item records.
EXPLAIN
SELECT
    o.order_id,
    o.order_status,
    i.order_item_id,
    i.price,
    i.freight_value
FROM olist_orders_dataset o
JOIN olist_order_items_dataset i
    ON o.order_id = i.order_id
WHERE o.order_status = 'delivered';

-- 19. Inspect an order-to-payment join.
-- This evaluates the execution plan for retrieving payment
-- records associated with orders.
EXPLAIN
SELECT
    o.order_id,
    o.order_status,
    p.payment_type,
    p.payment_value
FROM olist_orders_dataset o
JOIN olist_order_payments_dataset p
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';

-- 20. Inspect the analytical order summary.
-- Views can expand into joins and aggregations over their
-- underlying tables, depending on the view definition.
EXPLAIN
SELECT
    order_status,
    COUNT(*) AS order_count
FROM vw_order_summary
GROUP BY order_status;

-- 21. Inspect monthly order aggregation.
-- DATE_FORMAT is applied to the purchase timestamp for grouping.
-- The execution plan helps identify the access path and
-- aggregation operations used for the report.
EXPLAIN
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS order_count
FROM olist_orders_dataset
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;


-- ============================================================
-- SECTION 4: ACTUAL EXECUTION-PLAN ANALYSIS
-- ============================================================
-- EXPLAIN ANALYZE executes the query and reports actual
-- execution information alongside iterator estimates.
-- Available in MySQL 8.0.18 and later.
-- Use representative workloads because these statements
-- execute the underlying queries.


-- 22. Analyze the execution of order-item aggregation.
-- Compare estimated rows and actual rows to understand
-- the workload associated with item-level aggregation.
EXPLAIN ANALYZE
SELECT
    order_id,
    SUM(price) AS merchandise_value,
    SUM(freight_value) AS freight_value
FROM olist_order_items_dataset
GROUP BY order_id;

-- 23. Analyze the execution of payment aggregation.
-- This provides actual execution information for grouping
-- payment records by order.
EXPLAIN ANALYZE
SELECT
    order_id,
    SUM(payment_value) AS total_payment_value
FROM olist_order_payments_dataset
GROUP BY order_id;

-- 24. Analyze the execution of the analytical order summary.
-- This evaluates the cost of producing order-status counts
-- through the existing analytical view.
EXPLAIN ANALYZE
SELECT
    order_status,
    COUNT(*) AS order_count
FROM vw_order_summary
GROUP BY order_status;

-- 25. Analyze monthly order aggregation.
-- Actual iterator timings can help identify the cost of
-- scanning, grouping, and sorting records for monthly reporting.
EXPLAIN ANALYZE
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS order_count
FROM olist_orders_dataset
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;


-- ============================================================
-- SECTION 5: ANALYTICAL WORKLOAD OPTIMIZATION
-- ============================================================
-- Compare access patterns before changing indexes or query logic.
-- Index selection should reflect filtering, joining, sorting,
-- grouping, and the existing index definitions.


-- 26. Inspect the plan for a delivered-order date-range query.
-- The half-open interval includes the start date and excludes
-- the next month's start, avoiding end-of-day boundary issues.
EXPLAIN
SELECT
    order_id,
    order_purchase_timestamp,
    order_status
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_purchase_timestamp >= '2018-01-01'
  AND order_purchase_timestamp < '2018-02-01';

-- 27. Inspect the plan for a date-range order count.
-- This query keeps the timestamp predicate separate from
-- the month-formatting expression used in the report.
EXPLAIN
SELECT
    COUNT(*) AS order_count
FROM olist_orders_dataset
WHERE order_purchase_timestamp >= '2018-01-01'
  AND order_purchase_timestamp < '2018-02-01';

-- 28. Inspect the plan for order-level merchandise totals.
-- Pre-aggregating item data by order establishes the correct
-- grain before joining it to order-level reporting.
EXPLAIN
SELECT
    o.order_id,
    o.order_status,
    i.merchandise_value,
    i.freight_value
FROM olist_orders_dataset o
JOIN (
    SELECT
        order_id,
        SUM(price) AS merchandise_value,
        SUM(freight_value) AS freight_value
    FROM olist_order_items_dataset
    GROUP BY order_id
) i
    ON o.order_id = i.order_id
WHERE o.order_status = 'delivered';

-- 29. Inspect the plan for order-level payment totals.
-- Aggregating payments before joining avoids multiplying
-- order-level amounts by the number of payment records.
EXPLAIN
SELECT
    o.order_id,
    o.order_status,
    p.total_payment_value
FROM olist_orders_dataset o
JOIN (
    SELECT
        order_id,
        SUM(payment_value) AS total_payment_value
    FROM olist_order_payments_dataset
    GROUP BY order_id
) p
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';


-- ============================================================
-- SECTION 6: PERFORMANCE REVIEW AND OPTIMIZATION DECISIONS
-- ============================================================

-- 30. Review index size relative to table data size.
-- Large indexes consume storage but can improve access speed.
-- Their value depends on workload and actual index usage.
SELECT
    table_name,
    ROUND(data_length / 1024 / 1024, 2) AS data_size_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_size_mb,
    ROUND(
        100.0 * index_length
        / NULLIF(data_length + index_length, 0),
        2
    ) AS index_share_pct
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_type = 'BASE TABLE'
ORDER BY index_length DESC;

-- 31. Review the distribution of order statuses.
-- This describes the data volume behind status-based workloads
-- and helps contextualize the selectivity of status filters.
SELECT
    order_status,
    COUNT(*) AS order_count
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY order_count DESC;

-- 32. Review monthly order volumes.
-- Monthly volume provides context for choosing representative
-- periods when comparing execution plans.
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS order_count
FROM olist_orders_dataset
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- 33. Summarize table and index storage.
-- This helps identify tables that contribute most to the
-- database's physical storage footprint.
SELECT
    COUNT(*) AS total_tables,
    ROUND(SUM(data_length) / 1024 / 1024, 2) AS total_data_mb,
    ROUND(SUM(index_length) / 1024 / 1024, 2) AS total_index_mb,
    ROUND(
        SUM(data_length + index_length) / 1024 / 1024,
        2
    ) AS total_table_storage_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_type = 'BASE TABLE';


-- ============================================================
-- PERFORMANCE REVIEW NOTES
-- ============================================================
-- 1. Prefer indexed access for selective lookups when the
-- execution plan and workload justify it.
--
-- 2. Review full table scans in the context of table size.
-- A full scan may be appropriate when a query needs a large
-- proportion of the table.
--
-- 3. Compare estimated and actual rows from EXPLAIN ANALYZE.
-- Large differences can indicate inaccurate cardinality
-- estimates or data-distribution issues.
--
-- 4. Review joins and aggregations for unnecessary row
-- multiplication. Correct grain is essential for both
-- analytical accuracy and efficient execution.
--
-- 5. Evaluate candidate indexes against existing indexes
-- before creating new ones. Avoid duplicate or redundant
-- indexes that increase storage and write overhead.
--
-- 6. Compare performance under equivalent conditions.
-- Record query plans, actual timings, and result correctness
-- before and after any approved optimization.
--
-- 7. Index changes should be based on observed workload
-- evidence rather than the presence of a column alone.
