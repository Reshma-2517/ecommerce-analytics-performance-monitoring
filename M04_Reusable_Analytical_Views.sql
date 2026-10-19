-- ============================================================
-- MODULE: M04 - Reusable Analytical Views and Logic
-- PURPOSE: Create reusable analytical views for order,
--          payment, review, item, and category-level analysis.
--
-- IMPORTANT:
-- 1. This script does not modify or delete source records.
-- 2. Financial measures are aggregated separately by grain.
-- 3. Payment totals are not treated as merchandise revenue.
-- 4. Geolocation is excluded because ZIP codes may have
--    multiple coordinate records and multiply joins.
-- ============================================================

-- Set the target database for view creation and validation.
USE olist_analytics;


-- ============================================================
-- M04.1: ORDER ITEM SUMMARY
-- GRAIN: One row per order_id represented in order items.
-- PURPOSE: Aggregate item-level measures before joining them
--          to orders, payments, and reviews.
-- ============================================================

CREATE OR REPLACE VIEW vw_order_item_summary AS
SELECT
    oi.order_id,

    -- Count the source item records belonging to each order.
    COUNT(*) AS order_item_count,

    -- Count distinct products and sellers associated with each order.
    COUNT(DISTINCT oi.product_id) AS distinct_product_count,
    COUNT(DISTINCT oi.seller_id) AS distinct_seller_count,

    -- Separate merchandise value from freight charges.
    SUM(oi.price) AS merchandise_amount,
    SUM(oi.freight_value) AS freight_amount,

    -- Calculate the combined merchandise and freight amount.
    SUM(oi.price + oi.freight_value) AS item_plus_freight_amount

FROM olist_order_items_dataset AS oi

-- Aggregate the item records to one row per order.
GROUP BY oi.order_id;


-- ============================================================
-- M04.2: PAYMENT SUMMARY
-- GRAIN: One row per order_id represented in payments.
-- PURPOSE: Summarize payment records independently so payment
--          joins do not multiply order-item financial amounts.
-- ============================================================

CREATE OR REPLACE VIEW vw_order_payment_summary AS
SELECT
    p.order_id,

    -- Count payment records and distinct payment methods.
    COUNT(*) AS payment_record_count,
    COUNT(DISTINCT p.payment_type) AS distinct_payment_type_count,

    -- Sum the payment values recorded for each order.
    SUM(p.payment_value) AS payment_amount,

    -- Count payment records with a zero value.
    SUM(
        CASE
            WHEN p.payment_value = 0 THEN 1
            ELSE 0
        END
    ) AS zero_value_payment_count,

    -- Count payment records with a negative value.
    SUM(
        CASE
            WHEN p.payment_value < 0 THEN 1
            ELSE 0
        END
    ) AS negative_payment_count

FROM olist_order_payments_dataset AS p

-- Aggregate payments to one row per order.
GROUP BY p.order_id;


-- ============================================================
-- M04.3: REVIEW SUMMARY
-- GRAIN: One row per order_id represented in reviews.
-- PURPOSE: Summarize review counts and scores independently.
-- ============================================================

CREATE OR REPLACE VIEW vw_order_review_summary AS
SELECT
    r.order_id,

    -- Count all review records and non-NULL review scores.
    COUNT(*) AS review_record_count,
    COUNT(r.review_score) AS non_null_review_score_count,

    -- Calculate average and score range for each order.
    AVG(r.review_score) AS average_review_score,
    MIN(r.review_score) AS minimum_review_score,
    MAX(r.review_score) AS maximum_review_score

FROM olist_order_reviews_dataset AS r

-- Aggregate review records to one row per order.
GROUP BY r.order_id;


-- ============================================================
-- M04.4: CONSOLIDATED ORDER SUMMARY
-- GRAIN: Intended to be one row per source order.
-- PURPOSE: Combine order, customer, item, payment, review,
--          and delivery-timing information.
--
-- Items, payments, and reviews are aggregated independently
-- before joining to orders. This avoids multiplying totals.
-- ============================================================

CREATE OR REPLACE VIEW vw_order_summary AS
SELECT
    -- Order and customer identifiers.
    o.order_id,
    o.customer_id,
    c.customer_unique_id,

    -- Customer location attributes.
    c.customer_city,
    c.customer_state,

    -- Order status and lifecycle timestamps.
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- Item counts, with missing item summaries represented as zero.
    COALESCE(i.order_item_count, 0) AS order_item_count,
    COALESCE(i.distinct_product_count, 0) AS distinct_product_count,
    COALESCE(i.distinct_seller_count, 0) AS distinct_seller_count,

    -- Merchandise and freight measures are kept separate.
    COALESCE(i.merchandise_amount, 0)
        AS merchandise_amount,

    COALESCE(i.freight_amount, 0)
        AS freight_amount,

    COALESCE(i.item_plus_freight_amount, 0)
        AS item_plus_freight_amount,

    -- Payment measures remain separate from merchandise amounts.
    p.payment_record_count,
    p.distinct_payment_type_count,
    p.payment_amount,
    p.zero_value_payment_count,
    p.negative_payment_count,

    -- Review volume and score statistics.
    r.review_record_count,
    r.non_null_review_score_count,
    r.average_review_score,
    r.minimum_review_score,
    r.maximum_review_score,

    -- Calculate elapsed delivery time in days.
    -- Invalid or reversed timestamps produce NULL.
    CASE
        WHEN o.order_purchase_timestamp IS NOT NULL
         AND o.order_delivered_customer_date IS NOT NULL
         AND o.order_purchase_timestamp > '1000-01-01'
         AND o.order_delivered_customer_date > '1000-01-01'
         AND o.order_delivered_customer_date
                 >= o.order_purchase_timestamp
        THEN TIMESTAMPDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 24.0
        ELSE NULL
    END AS delivery_days,

    -- Calculate the estimated delivery duration from purchase.
    -- This uses the estimated delivery timestamp, not the actual one.
    CASE
        WHEN o.order_purchase_timestamp IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
         AND o.order_purchase_timestamp > '1000-01-01'
         AND o.order_estimated_delivery_date > '1000-01-01'
        THEN DATEDIFF(
            o.order_estimated_delivery_date,
            o.order_purchase_timestamp
        )
        ELSE NULL
    END AS estimated_delivery_days_from_purchase,

    -- Compare the actual delivery date with the estimated date.
    -- Positive values indicate delivery after the estimate;
    -- negative values indicate delivery before the estimate.
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
         AND o.order_delivered_customer_date > '1000-01-01'
         AND o.order_estimated_delivery_date > '1000-01-01'
        THEN DATEDIFF(
            DATE(o.order_delivered_customer_date),
            DATE(o.order_estimated_delivery_date)
        )
        ELSE NULL
    END AS delivery_vs_estimate_days

-- The orders table establishes the primary row population.
FROM olist_orders_dataset AS o

-- Add customer attributes using the customer identifier.
LEFT JOIN olist_customers_dataset AS c
    ON o.customer_id = c.customer_id

-- Attach the independently aggregated order-item measures.
LEFT JOIN vw_order_item_summary AS i
    ON o.order_id = i.order_id

-- Attach the independently aggregated payment measures.
LEFT JOIN vw_order_payment_summary AS p
    ON o.order_id = p.order_id

-- Attach the independently aggregated review measures.
LEFT JOIN vw_order_review_summary AS r
    ON o.order_id = r.order_id;


-- ============================================================
-- M04.5: ORDER ITEM DETAIL
-- GRAIN: One row per source order-item record.
-- PURPOSE: Provide detailed item-level data enriched with
--          product category and seller location attributes.
--
-- Product and seller attributes are descriptive. This view
-- deliberately excludes geolocation.
-- ============================================================

CREATE OR REPLACE VIEW vw_order_item_detail AS
SELECT
    -- Identifiers and shipping deadline from the item record.
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.shipping_limit_date,

    -- Financial measures at the individual item-record grain.
    oi.price AS item_price,
    oi.freight_value AS item_freight_value,
    oi.price + oi.freight_value AS item_plus_freight_amount,

    -- Product category provides a basis for category analysis.
    pr.product_category_name,

    -- Seller location attributes support geographic summaries.
    s.seller_city,
    s.seller_state

FROM olist_order_items_dataset AS oi

-- Retain item rows even when product attributes are unavailable.
LEFT JOIN olist_products_dataset AS pr
    ON oi.product_id = pr.product_id

-- Retain item rows even when seller attributes are unavailable.
LEFT JOIN olist_sellers_dataset AS s
    ON oi.seller_id = s.seller_id;


-- ============================================================
-- M04.6: CATEGORY PERFORMANCE
-- GRAIN: One row per product category, including NULL category.
-- PURPOSE: Summarize item volume, commercial amounts, and
--          average item prices and freight values by category.
--
-- Counts and amounts are based on order-item records.
-- Orders can appear in multiple categories.
-- ============================================================

CREATE OR REPLACE VIEW vw_category_performance AS
SELECT
    -- Category name; NULL remains a separate grouping.
    d.product_category_name,

    -- Volume measures at the order-item grain.
    COUNT(*) AS order_item_count,
    COUNT(DISTINCT d.order_id) AS distinct_order_count,
    COUNT(DISTINCT d.product_id) AS distinct_product_count,
    COUNT(DISTINCT d.seller_id) AS distinct_seller_count,

    -- Total commercial amounts for items in each category.
    SUM(d.item_price) AS merchandise_amount,
    SUM(d.item_freight_value) AS freight_amount,
    SUM(d.item_plus_freight_amount) AS item_plus_freight_amount,

    -- Average price and freight per item record.
    AVG(d.item_price) AS average_item_price,
    AVG(d.item_freight_value) AS average_item_freight

FROM vw_order_item_detail AS d

-- Produce one aggregated row per product category.
GROUP BY d.product_category_name;


-- ============================================================
-- END OF M04 VIEW DEFINITIONS
-- ============================================================


-- ============================================================
-- M04 VALIDATION TESTS
-- PURPOSE: Verify view creation, grain, financial reconciliation,
--          and potential row multiplication from joins.
-- ============================================================

-- Select the analytics database for the validation queries.
USE olist_analytics;


-- ------------------------------------------------------------
-- TEST 1: Confirm all six views exist.
-- Review the output for the expected view names.
-- ------------------------------------------------------------

SHOW FULL TABLES
WHERE Table_type = 'VIEW';


-- ------------------------------------------------------------
-- TEST 2: Check whether order_id is unique in the source.
-- Expected: no rows if order_id is unique.
-- ------------------------------------------------------------

SELECT
    order_id,
    COUNT(*) AS occurrences
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1
LIMIT 20;


-- ------------------------------------------------------------
-- TEST 3: Compare source order count with order summary count.
-- These counts should match if order_id is unique and the
-- customer join does not multiply source orders.
-- ------------------------------------------------------------

SELECT
    (SELECT COUNT(*)
     FROM olist_orders_dataset) AS source_order_rows,

    (SELECT COUNT(*)
     FROM vw_order_summary) AS summary_rows;


-- ------------------------------------------------------------
-- TEST 4: Reconcile merchandise and freight amounts.
-- Compare the source totals with the independently aggregated
-- order-item summary totals.
-- Differences should be zero, subject to matching source values.
-- ------------------------------------------------------------

SELECT
    (SELECT SUM(price)
     FROM olist_order_items_dataset) AS source_merchandise,

    (SELECT SUM(merchandise_amount)
     FROM vw_order_item_summary) AS summarized_merchandise,

    (SELECT SUM(freight_value)
     FROM olist_order_items_dataset) AS source_freight,

    (SELECT SUM(freight_amount)
     FROM vw_order_item_summary) AS summarized_freight;


-- ------------------------------------------------------------
-- TEST 5: Compare payment totals independently.
-- The two values should reconcile if all source payment records
-- are included in the order-level payment summary.
--
-- This must not be compared to merchandise revenue as though
-- they were the same financial measure.
-- ------------------------------------------------------------

SELECT
    (SELECT SUM(payment_value)
     FROM olist_order_payments_dataset) AS source_payment_total,

    (SELECT SUM(payment_amount)
     FROM vw_order_payment_summary) AS summarized_payment_total;


-- ------------------------------------------------------------
-- TEST 6: Inspect consolidated order records.
-- This provides a sample of recent orders and their associated
-- customer, financial, review, and delivery attributes.
-- ------------------------------------------------------------

SELECT *
FROM vw_order_summary
ORDER BY order_purchase_timestamp DESC
LIMIT 20;


-- ------------------------------------------------------------
-- TEST 7: Inspect category performance.
-- Sort by merchandise amount to review the largest categories
-- by the measure used in this view.
-- ------------------------------------------------------------

SELECT *
FROM vw_category_performance
ORDER BY merchandise_amount DESC
LIMIT 20;


-- ------------------------------------------------------------
-- TEST 8: Check whether order-item detail multiplies source rows.
-- Expected: equal counts if product_id and seller_id are unique
-- in their respective dimension tables.
-- ------------------------------------------------------------

SELECT
    (SELECT COUNT(*)
     FROM olist_order_items_dataset) AS source_item_rows,

    (SELECT COUNT(*)
     FROM vw_order_item_detail) AS detail_view_rows;


-- ------------------------------------------------------------
-- TEST 9: Check whether customer IDs are unique.
-- Expected: no rows if customer_id is unique.
-- Duplicate customer IDs could multiply rows in vw_order_summary.
-- ------------------------------------------------------------

SELECT
    customer_id,
    COUNT(*) AS occurrences
FROM olist_customers_dataset
GROUP BY customer_id
HAVING COUNT(*) > 1
LIMIT 20;


-- ------------------------------------------------------------
-- TEST 10: Check whether product and seller IDs are unique.
-- Expected: no rows for each query if IDs are unique.
-- Duplicate dimension keys could multiply records in the
-- order-item detail view and affect category aggregates.
-- ------------------------------------------------------------

SELECT product_id, COUNT(*) AS occurrences
FROM olist_products_dataset
GROUP BY product_id
HAVING COUNT(*) > 1
LIMIT 20;

SELECT seller_id, COUNT(*) AS occurrences
FROM olist_sellers_dataset
GROUP BY seller_id
HAVING COUNT(*) > 1
LIMIT 20;