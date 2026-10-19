-- ============================================================
-- PROJECT: MySQL Analytics Intelligence & Business Performance
--          Control Framework
-- MODULE: M02 - Data Profiling and Data Quality Investigation
-- DATABASE: olist_analytics
--
-- OBJECTIVE:
-- Examine relationships between source tables, profile payment
-- and review data, and investigate potential data-quality issues.
--
-- ANALYST APPROACH:
-- Identify exceptions first, quantify their frequency, and then
-- inspect individual records where further investigation is needed.
-- ============================================================


-- ============================================================
-- SECTION 1: REFERENTIAL INTEGRITY VALIDATION
-- PURPOSE:
-- Identify records that reference entities missing from the
-- corresponding parent table.
--
-- METHOD:
-- LEFT JOIN retains records from the source table. A NULL
-- parent identifier indicates that no matching record exists.
--
-- OUTPUT:
-- One row per relationship, with the number of orphan records.
-- ============================================================

USE olist_analytics;

-- 1. Orders referencing customers that do not exist
SELECT
    'orders_to_customers' AS relationship_name,
    COUNT(*) AS orphan_rows
FROM olist_orders_dataset o
LEFT JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL

-- 2. Order items referencing orders that do not exist
SELECT
    'items_to_orders',
    COUNT(*)
FROM olist_order_items_dataset i
LEFT JOIN olist_orders_dataset o
    ON i.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

-- 3. Order items referencing missing products
SELECT
    'items_to_products',
    COUNT(*)
FROM olist_order_items_dataset i
LEFT JOIN olist_products_dataset p
    ON i.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

-- 4. Order items referencing missing sellers
SELECT
    'items_to_sellers',
    COUNT(*)
FROM olist_order_items_dataset i
LEFT JOIN olist_sellers_dataset s
    ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

-- 5. Payments referencing missing orders
SELECT
    'payments_to_orders',
    COUNT(*)
FROM olist_order_payments_dataset p
LEFT JOIN olist_orders_dataset o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

-- 6. Reviews referencing missing orders
SELECT
    'reviews_to_orders',
    COUNT(*)
FROM olist_order_reviews_dataset r
LEFT JOIN olist_orders_dataset o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


-- ============================================================
-- SECTION 2: PAYMENT DATA PROFILING
-- PURPOSE:
-- Assess payment-record completeness and identify unusual
-- payment values before performing financial reconciliation.
--
-- METRICS:
-- - Total number of payment records
-- - Missing order identifiers and payment values
-- - Negative and zero payment values
-- - Minimum and maximum recorded payment values
-- ============================================================

USE olist_analytics;

-- 1. Payment data profile
SELECT
    COUNT(*) AS total_rows,
    SUM(order_id IS NULL) AS null_order_ids,
    SUM(payment_value IS NULL) AS null_payment_values,
    SUM(payment_value < 0) AS negative_payment_values,
    SUM(payment_value = 0) AS zero_payment_values,
    MIN(payment_value) AS min_payment_value,
    MAX(payment_value) AS max_payment_value
FROM olist_order_payments_dataset;


-- ============================================================
-- SECTION 3: REVIEW DATA PROFILING
-- PURPOSE:
-- Evaluate review completeness, score validity, and identifier
-- uniqueness to understand the structure of the review dataset.
--
-- VALIDATION:
-- Review scores are expected to fall within the range 1–5.
-- Duplicate review identifiers are investigated separately
-- rather than automatically treated as invalid records.
-- ============================================================

-- 2. Review data profile
SELECT
    COUNT(*) AS total_rows,
    SUM(order_id IS NULL) AS null_order_ids,
    SUM(review_score IS NULL) AS null_review_scores,
    SUM(review_score NOT BETWEEN 1 AND 5)
        AS invalid_review_scores,
    MIN(review_score) AS min_review_score,
    MAX(review_score) AS max_review_score,
    COUNT(DISTINCT review_id) AS distinct_review_ids
FROM olist_order_reviews_dataset;


-- ============================================================
-- SECTION 4: IDENTIFY DUPLICATE REVIEW IDENTIFIERS
-- PURPOSE:
-- List review IDs appearing in multiple records.
--
-- ANALYST USE:
-- Helps determine whether repeated identifiers represent
-- duplicate records or multiple records requiring investigation.
--
-- OUTPUT:
-- Up to 20 review IDs, ordered by their occurrence count.
-- ============================================================

-- 3. Check duplicate review IDs
SELECT
    review_id,
    COUNT(*) AS occurrences
FROM olist_order_reviews_dataset
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;


-- ============================================================
-- SECTION 5: INVESTIGATE ZERO-VALUE PAYMENTS
-- PURPOSE:
-- Retrieve individual payment records where the recorded
-- payment value is zero.
--
-- ANALYST USE:
-- Enables record-level investigation of exceptions identified
-- during the payment data profile.
-- ============================================================

SELECT *
FROM olist_order_payments_dataset
WHERE payment_value = 0
ORDER BY order_id, payment_sequential;


-- ============================================================
-- SECTION 6: PROFILE DUPLICATE REVIEW GROUPS
-- PURPOSE:
-- Examine repeated review IDs using additional attributes.
--
-- METRICS:
-- - Number of records per review ID
-- - Number of distinct associated orders
-- - Number of distinct review scores
-- - Number of distinct comment titles and messages
--
-- ANALYST USE:
-- Helps assess whether repeated IDs have consistent associated
-- data or require closer inspection.
-- ============================================================

SELECT
    review_id,
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT review_score) AS distinct_scores,
    COUNT(DISTINCT review_comment_title)
        AS distinct_titles,
    COUNT(DISTINCT review_comment_message)
        AS distinct_messages
FROM olist_order_reviews_dataset
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, review_id
LIMIT 20;


-- ============================================================
-- SECTION 7: INVESTIGATE ALL PAYMENT RECORDS FOR AFFECTED ORDERS
-- PURPOSE:
-- Retrieve every payment record for orders that contain at
-- least one zero-value payment.
--
-- ANALYST USE:
-- Provides the full payment-record context for affected orders,
-- rather than examining zero-value rows in isolation.
-- ============================================================

SELECT *
FROM olist_order_payments_dataset
WHERE order_id IN (
    SELECT order_id
    FROM olist_order_payments_dataset
    WHERE payment_value = 0
)
ORDER BY order_id, payment_sequential;


-- ============================================================
-- SECTION 8: IDENTIFY A DUPLICATE REVIEW ID FOR INVESTIGATION
-- PURPOSE:
-- Return the review ID with the highest occurrence count
-- among IDs appearing more than once.
--
-- ANALYST USE:
-- Selects one candidate for detailed record-level inspection.
-- ============================================================

USE olist_analytics;

SELECT
    review_id,
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM olist_order_reviews_dataset
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 1;


-- ============================================================
-- SECTION 9: INSPECT A SPECIFIC REVIEW ID
-- PURPOSE:
-- Retrieve the records associated with a selected review ID
-- for direct comparison and investigation.
--
-- NOTE:
-- The review ID is preserved exactly as supplied in the
-- original SQL.
-- ============================================================

SELECT *
FROM olist_order_reviews_dataset
WHERE review_id = '08528f70f579f0c830189efc523d2182';


-- ============================================================
-- SECTION 10: VALIDATE REVIEW-ORDER PAIR UNIQUENESS
-- PURPOSE:
-- Compare total review rows with distinct review/order pairs
-- and measure missing review and order identifiers.
--
-- ANALYST USE:
-- Assesses uniqueness at the review-order pair level, which
-- is different from checking review_id alone.
-- ============================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT review_id, order_id) AS distinct_review_order_pairs,
    SUM(review_id IS NULL) AS null_review_ids,
    SUM(order_id IS NULL) AS null_order_ids
FROM olist_order_reviews_dataset;


-- ============================================================
-- SECTION 11: IDENTIFY DUPLICATE REVIEW-ORDER PAIRS
-- PURPOSE:
-- List review/order combinations appearing more than once.
--
-- ANALYST USE:
-- Provides a targeted record-level view of repeated pairs
-- for further data-quality investigation.
-- ============================================================

SELECT
    review_id,
    order_id,
    COUNT(*) AS occurrences
FROM olist_order_reviews_dataset
GROUP BY review_id, order_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;

-- ============================================================
-- SECTION 12: PROFILE ORDER TIMESTAMP COMPLETENESS
-- PURPOSE:
-- Assess the availability of key timestamps throughout the
-- order lifecycle, from purchase through delivery.
--
-- METRICS:
-- - Missing purchase, approval, carrier, and delivery dates
-- - Missing estimated delivery dates
-- - Approval dates earlier than purchase dates
-- - Delivery dates earlier than carrier handoff or purchase
--
-- ANALYST USE:
-- Establishes an initial view of timestamp completeness and
-- chronological consistency before delivery analysis.
-- ============================================================

USE olist_analytics;

SELECT
    COUNT(*) AS total_orders,

    SUM(order_purchase_timestamp IS NULL)
        AS null_purchase_dates,

    SUM(order_approved_at IS NULL)
        AS null_approval_dates,

    SUM(order_delivered_carrier_date IS NULL)
        AS null_carrier_dates,

    SUM(order_delivered_customer_date IS NULL)
        AS null_delivery_dates,

    SUM(order_estimated_delivery_date IS NULL)
        AS null_estimated_dates,

    SUM(
        order_approved_at < order_purchase_timestamp
    ) AS approval_before_purchase,

    SUM(
        order_delivered_customer_date
        < order_delivered_carrier_date
    ) AS delivery_before_carrier,

    SUM(
        order_delivered_customer_date
        < order_purchase_timestamp
    ) AS delivery_before_purchase

FROM olist_orders_dataset;


-- ============================================================
-- SECTION 13: IDENTIFY ORDERS WITH CHRONOLOGICAL ANOMALIES
-- PURPOSE:
-- Retrieve individual orders whose timestamps indicate an
-- unexpected sequence in the order lifecycle.
--
-- ANALYST USE:
-- Provides record-level context for investigating anomalies
-- identified by the aggregate timestamp profile.
--
-- OUTPUT:
-- Returns the relevant timestamps and binary indicators
-- for the three chronological conditions being tested.
-- ============================================================

SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,

    CASE
        WHEN order_approved_at < order_purchase_timestamp
        THEN 1 ELSE 0
    END AS approval_before_purchase,

    CASE
        WHEN order_delivered_customer_date
             < order_delivered_carrier_date
        THEN 1 ELSE 0
    END AS delivery_before_carrier,

    CASE
        WHEN order_delivered_customer_date
             < order_purchase_timestamp
        THEN 1 ELSE 0
    END AS delivery_before_purchase

FROM olist_orders_dataset
WHERE
    order_approved_at < order_purchase_timestamp
    OR order_delivered_customer_date
       < order_delivered_carrier_date
    OR order_delivered_customer_date
       < order_purchase_timestamp
ORDER BY order_purchase_timestamp
LIMIT 50;


-- ============================================================
-- SECTION 14: PROFILE ZERO DATES BY ORDER STATUS
-- PURPOSE:
-- Examine the distribution of zero-date timestamps across
-- order statuses.
--
-- METRICS:
-- - Total orders per status
-- - Zero approval dates
-- - Zero carrier-handoff dates
-- - Zero customer-delivery dates
--
-- ANALYST USE:
-- Helps determine whether zero-date values are concentrated
-- in particular order statuses and require further review.
-- ============================================================

USE olist_analytics;

SELECT
    order_status,
    COUNT(*) AS total_orders,

    SUM(
        DATE_FORMAT(order_approved_at, '%Y-%m-%d %H:%i:%s')
        = '0000-00-00 00:00:00'
    ) AS zero_approval_dates,

    SUM(
        DATE_FORMAT(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s')
        = '0000-00-00 00:00:00'
    ) AS zero_carrier_dates,

    SUM(
        DATE_FORMAT(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s')
        = '0000-00-00 00:00:00'
    ) AS zero_delivery_dates

FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;


-- ============================================================
-- SECTION 15: CLASSIFY CHRONOLOGICAL ANOMALIES
-- PURPOSE:
-- Retrieve anomalous orders and label each record according
-- to the first matching chronological condition.
--
-- VALIDATION CONDITIONS:
-- - Approval before purchase
-- - Customer delivery before carrier handoff
-- - Customer delivery before purchase
--
-- ANALYST USE:
-- Adds a readable anomaly classification to support
-- investigation of individual order records.
--
-- DATE GUARDS:
-- The query excludes NULL and very early date values for the
-- relevant comparisons to avoid treating zero or invalid
-- dates as ordinary timestamps.
-- ============================================================

SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,

    CASE
        WHEN order_approved_at < order_purchase_timestamp
            THEN 'Approval before purchase'
        WHEN order_delivered_customer_date
             < order_delivered_carrier_date
            THEN 'Delivery before carrier handoff'
        WHEN order_delivered_customer_date
             < order_purchase_timestamp
            THEN 'Delivery before purchase'
    END AS anomaly_type

FROM olist_orders_dataset
WHERE
    order_approved_at IS NOT NULL
    AND order_purchase_timestamp IS NOT NULL
    AND order_approved_at > '1000-01-01'
    AND order_purchase_timestamp > '1000-01-01'
    AND order_approved_at < order_purchase_timestamp

    OR (
        order_delivered_customer_date IS NOT NULL
        AND order_delivered_carrier_date IS NOT NULL
        AND order_delivered_customer_date > '1000-01-01'
        AND order_delivered_carrier_date > '1000-01-01'
        AND order_delivered_customer_date
            < order_delivered_carrier_date
    )

    OR (
        order_delivered_customer_date IS NOT NULL
        AND order_purchase_timestamp IS NOT NULL
        AND order_delivered_customer_date > '1000-01-01'
        AND order_purchase_timestamp > '1000-01-01'
        AND order_delivered_customer_date
            < order_purchase_timestamp
    )
LIMIT 100;


-- ============================================================
-- SECTION 16: RECOUNT CHRONOLOGICAL ANOMALIES WITH DATE GUARDS
-- PURPOSE:
-- Quantify the three timestamp anomalies while excluding
-- NULL and very early date values from the comparisons.
--
-- ANALYST USE:
-- Provides aggregate counts that can be compared with the
-- initial timestamp profile and record-level investigation.
-- ============================================================

USE olist_analytics;

SELECT
    SUM(
        order_approved_at < order_purchase_timestamp
        AND order_approved_at > '1000-01-01'
        AND order_purchase_timestamp > '1000-01-01'
    ) AS approval_before_purchase,

    SUM(
        order_delivered_customer_date
            < order_delivered_carrier_date
        AND order_delivered_customer_date > '1000-01-01'
        AND order_delivered_carrier_date > '1000-01-01'
    ) AS delivery_before_carrier,

    SUM(
        order_delivered_customer_date
            < order_purchase_timestamp
        AND order_delivered_customer_date > '1000-01-01'
        AND order_purchase_timestamp > '1000-01-01'
    ) AS delivery_before_purchase

FROM olist_orders_dataset;
-- ============================================================
-- M02: DATA PROFILING, RELATIONSHIP VALIDATION,
--      AND FINANCIAL RECONCILIATION
-- PART 3 OF 4: FINANCIAL RECONCILIATION
-- ============================================================


-- ------------------------------------------------------------
-- 1. OVERALL FINANCIAL RECONCILIATION
-- ------------------------------------------------------------
-- PURPOSE:
-- Compare order-item value plus freight charges with recorded payments.
-- Aggregate item and payment records separately at order level before
-- joining them, avoiding multiplication of totals caused by many-to-many
-- relationships between item records and payment records.
--
-- KEY METRICS:
-- matched_orders: Orders present in both aggregated datasets.
-- total_item_value: Sum of product prices.
-- total_freight_value: Sum of freight charges.
-- total_item_plus_freight: Combined item and freight value.
-- total_payments: Sum of recorded payments for matched orders.
-- total_difference: Payments minus item-plus-freight value.
-- orders_with_difference_over_1_cent: Orders whose absolute difference
-- exceeds R$0.01.

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS item_value,
        SUM(freight_value) AS freight_value,
        SUM(price + freight_value) AS item_plus_freight
    FROM olist_order_items_dataset
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        COUNT(*) AS payment_record_count
    FROM olist_order_payments_dataset
    GROUP BY order_id
)
SELECT
    COUNT(*) AS matched_orders,
    SUM(i.item_value) AS total_item_value,
    SUM(i.freight_value) AS total_freight_value,
    SUM(i.item_plus_freight) AS total_item_plus_freight,
    SUM(p.payment_total) AS total_payments,
    SUM(p.payment_total - i.item_plus_freight)
        AS total_difference,
    SUM(
        ABS(p.payment_total - i.item_plus_freight) > 0.01
    ) AS orders_with_difference_over_1_cent
FROM item_totals i
JOIN payment_totals p
    ON i.order_id = p.order_id;



-- ------------------------------------------------------------
-- 2. IDENTIFY ORDERS WITH FINANCIAL DISCREPANCIES
-- ------------------------------------------------------------
-- PURPOSE:
-- List individual orders whose payment total differs from the sum of
-- item prices and freight charges by more than one cent.
--
-- ANALYTICAL APPROACH:
-- Aggregate item and payment records independently at order level.
-- Join the aggregated results to the orders table to retrieve status.
-- Calculate the payment difference and sort by absolute discrepancy.
-- Return the 30 largest discrepancies for detailed investigation.
--
-- INTERPRETATION:
-- A discrepancy is a signal for investigation, not automatic proof
-- of fraud, non-payment, or incorrect data.

USE olist_analytics;

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS item_value,
        SUM(freight_value) AS freight_value
    FROM olist_order_items_dataset
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        COUNT(*) AS payment_record_count
    FROM olist_order_payments_dataset
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_status,
    i.item_value,
    i.freight_value,
    p.payment_total,
    p.payment_record_count,
    ROUND(
        p.payment_total - (i.item_value + i.freight_value),
        2
    ) AS difference
FROM olist_orders_dataset o
JOIN item_totals i
    ON o.order_id = i.order_id
JOIN payment_totals p
    ON o.order_id = p.order_id
WHERE ABS(
    p.payment_total - (i.item_value + i.freight_value)
) > 0.01
ORDER BY ABS(
    p.payment_total - (i.item_value + i.freight_value)
) DESC
LIMIT 30;



-- ------------------------------------------------------------
-- 3. INSPECT ITEM AND PAYMENT RECORDS FOR A SELECTED ORDER
-- ------------------------------------------------------------
-- PURPOSE:
-- Display the underlying item and payment records for a specific order.
--
-- UNION ALL combines both record types into a common output structure.
-- ITEM rows show product references, item prices, and freight charges.
-- PAYMENT rows show payment sequence, payment type, and payment value.
-- NULL represents freight in payment rows because the payment table
-- does not provide a corresponding freight-value field.
--
-- USE CASE:
-- Investigate the individual records behind an aggregate discrepancy.

SELECT
    'ITEM' AS record_type,
    order_id,
    order_item_id AS sequence_no,
    product_id AS reference_id,
    price AS amount,
    freight_value AS freight
FROM olist_order_items_dataset
WHERE order_id = 'ce6d150fb29ad17d2082f4847107665'

UNION ALL

SELECT
    'PAYMENT',
    order_id,
    payment_sequential,
    payment_type,
    payment_value,
    NULL
FROM olist_order_payments_dataset
WHERE order_id = 'ce6d150fb29ad17d2082f4847107665';



-- ------------------------------------------------------------
-- 4. COUNT ORDERS WITHOUT ITEM OR PAYMENT RECORDS
-- ------------------------------------------------------------
-- PURPOSE:
-- Determine how many orders lack associated item records, payment
-- records, or both.
--
-- The CTEs reduce each detail table to one row per order.
-- LEFT JOIN preserves every order, including orders without matches.
-- NULL checks identify missing relationships.
--
-- KEY METRICS:
-- total_orders: Total orders represented in the orders table.
-- orders_without_items: Orders with no matching item records.
-- orders_without_payments: Orders with no matching payment records.
-- orders_without_either: Orders missing both item and payment records.

WITH item_totals AS (
    SELECT order_id
    FROM olist_order_items_dataset
    GROUP BY order_id
),
payment_totals AS (
    SELECT order_id
    FROM olist_order_payments_dataset
    GROUP BY order_id
)
SELECT
    COUNT(*) AS total_orders,
    SUM(i.order_id IS NULL) AS orders_without_items,
    SUM(p.order_id IS NULL) AS orders_without_payments,
    SUM(
        i.order_id IS NULL AND p.order_id IS NULL
    ) AS orders_without_either
FROM olist_orders_dataset o
LEFT JOIN item_totals i ON o.order_id = i.order_id
LEFT JOIN payment_totals p ON o.order_id = p.order_id;



-- ------------------------------------------------------------
-- 5. RETRIEVE THE SINGLE LARGEST FINANCIAL DISCREPANCY
-- ------------------------------------------------------------
-- PURPOSE:
-- Isolate the order with the largest absolute difference between
-- its recorded payment total and item-plus-freight value.
--
-- The calculation is performed at order level after aggregating
-- the item and payment tables separately.
-- ORDER BY ranks the absolute differences in descending order.
-- LIMIT 1 returns only the highest-ranked discrepancy.
--
-- USE CASE:
-- Select a single order for focused investigation of its status,
-- item value, freight charges, payment total, and calculated difference.

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS item_value,
        SUM(freight_value) AS freight_value
    FROM olist_order_items_dataset
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total
    FROM olist_order_payments_dataset
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_status,
    i.item_value,
    i.freight_value,
    p.payment_total,
    ROUND(
        p.payment_total - (i.item_value + i.freight_value),
        2
    ) AS difference
FROM olist_orders_dataset o
JOIN item_totals i ON o.order_id = i.order_id
JOIN payment_totals p ON o.order_id = p.order_id
WHERE ABS(
    p.payment_total - (i.item_value + i.freight_value)
) > 0.01
ORDER BY ABS(
    p.payment_total - (i.item_value + i.freight_value)
) DESC
LIMIT 1;



-- ------------------------------------------------------------
-- 6. RETRIEVE RAW RECORDS FOR ANOTHER SELECTED ORDER
-- ------------------------------------------------------------
-- PURPOSE:
-- Retrieve all columns from the item and payment tables for a
-- particular order, supporting a more detailed record-level review.
--
-- These SELECT statements are kept separate so each table's original
-- structure and fields can be inspected independently.
--
-- NOTE:
-- The order identifier below is preserved exactly as supplied.

SELECT *
FROM olist_order_items_dataset
WHERE order_id = 'ce6d150fb29ada17d2082f4847107665';

SELECT *
FROM olist_order_payments_dataset
WHERE order_id = 'ce6d150fb29ada17d2082f4847107665';



-- ------------------------------------------------------------
-- 7. ANALYZE FINANCIAL DIFFERENCES BY INSTALLMENT GROUP
-- ------------------------------------------------------------
-- PURPOSE:
-- Investigate whether financial discrepancies vary across groups
-- defined by the total number of payment installments.
--
-- CTE LOGIC:
-- item_totals:
--     Calculates the item-plus-freight total for each order.
-- payment_totals:
--     Aggregates payment values, installment counts, and payment
--     record counts for each order.
-- order_reconciliation:
--     Combines the two aggregates and calculates the difference.
--
-- INSTALLMENT GROUPS:
-- 1 installment
-- 2-6 installments
-- 7-12 installments
-- 13+ installments
--
-- OUTPUT METRICS:
-- orders: Number of matched orders in each installment group.
-- orders_with_difference: Number of orders with an absolute
-- difference greater than R$0.01.
-- average_difference: Average signed payment difference.
-- total_difference: Sum of signed payment differences.
--
-- INTERPRETATION:
-- Positive differences indicate recorded payments exceed the
-- item-plus-freight total; negative differences indicate the reverse.
-- These results describe associations in the data and do not establish
-- that installment count causes financial discrepancies.

USE olist_analytics;

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS item_plus_freight
    FROM olist_order_items_dataset
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        SUM(payment_installments) AS total_installments,
        COUNT(*) AS payment_records
    FROM olist_order_payments_dataset
    GROUP BY order_id
),
order_reconciliation AS (
    SELECT
        i.order_id,
        i.item_plus_freight,
        p.payment_total,
        p.total_installments,
        p.payment_records,
        p.payment_total - i.item_plus_freight AS difference
    FROM item_totals i
    JOIN payment_totals p
        ON i.order_id = p.order_id
)
SELECT
    CASE
        WHEN total_installments = 1 THEN '1 installment'
        WHEN total_installments BETWEEN 2 AND 6 THEN '2-6 installments'
        WHEN total_installments BETWEEN 7 AND 12 THEN '7-12 installments'
        ELSE '13+ installments'
    END AS installment_group,
    COUNT(*) AS orders,
    SUM(ABS(difference) > 0.01) AS orders_with_difference,
    ROUND(AVG(difference), 2) AS average_difference,
    ROUND(SUM(difference), 2) AS total_difference
FROM order_reconciliation
GROUP BY installment_group
ORDER BY installment_group;

USE olist_analytics;

-- =====================================================
-- A. TABLE ROW COUNTS
-- =====================================================
-- PURPOSE:
-- Count the records in each of the nine source tables.
-- This provides a baseline for data-volume validation and
-- helps identify unexpected missing or additional records.
--
-- UNION ALL combines the individual table counts into one result.
-- It retains every row without performing duplicate elimination.

SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM olist_customers_dataset
UNION ALL
SELECT 'geolocation', COUNT(*)
FROM olist_geolocation_dataset
UNION ALL
SELECT 'order_items', COUNT(*)
FROM olist_order_items_dataset
UNION ALL
SELECT 'order_payments', COUNT(*)
FROM olist_order_payments_dataset
UNION ALL
SELECT 'order_reviews', COUNT(*)
FROM olist_order_reviews_dataset
UNION ALL
SELECT 'orders', COUNT(*)
FROM olist_orders_dataset
UNION ALL
SELECT 'products', COUNT(*)
FROM olist_products_dataset
UNION ALL
SELECT 'sellers', COUNT(*)
FROM olist_sellers_dataset
UNION ALL
SELECT 'category_translation', COUNT(*)
FROM product_category_name_translation;


-- =====================================================
-- B. FINANCIAL RECONCILIATION BY ORDER STATUS
-- =====================================================
-- PURPOSE:
-- Compare item value, freight value, and recorded payment totals
-- across different order statuses.
--
-- The CTEs aggregate item and payment records separately at order
-- level before joining them to the orders table.
--
-- KEY METRICS:
-- matched_orders: Orders represented in both aggregated datasets.
-- item_value: Total product prices by order status.
-- freight_value: Total freight charges by order status.
-- payment_total: Total recorded payments by order status.
-- net_difference: Payments minus item value minus freight value.
-- orders_over_one_cent: Matched orders with an absolute difference
-- greater than R$0.01.
--
-- INTERPRETATION:
-- Differences by status may help identify patterns for investigation.
-- These results cover matched orders, not orders missing items or
-- payment records.

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS item_value,
        SUM(freight_value) AS freight_value
    FROM olist_order_items_dataset
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total
    FROM olist_order_payments_dataset
    GROUP BY order_id
)
SELECT
    o.order_status,
    COUNT(*) AS matched_orders,
    ROUND(SUM(i.item_value), 2) AS item_value,
    ROUND(SUM(i.freight_value), 2) AS freight_value,
    ROUND(SUM(p.payment_total), 2) AS payment_total,
    ROUND(
        SUM(p.payment_total - i.item_value - i.freight_value),
        2
    ) AS net_difference,
    SUM(
        ABS(p.payment_total - i.item_value - i.freight_value) > 0.01
    ) AS orders_over_one_cent
FROM olist_orders_dataset o
JOIN item_totals i
    ON o.order_id = i.order_id
JOIN payment_totals p
    ON o.order_id = p.order_id
GROUP BY o.order_status
ORDER BY o.order_status;


-- =====================================================
-- C. ORDERS WITHOUT ITEMS OR PAYMENTS
-- =====================================================
-- PURPOSE:
-- Count orders without associated item records or payment records,
-- grouped by order status.
--
-- DISTINCT produces one order identifier per CTE, preventing
-- multiple item or payment records from multiplying order counts.
-- LEFT JOIN preserves orders even when a matching record is absent.
-- NULL checks identify missing relationships.

WITH item_orders AS (
    SELECT DISTINCT order_id
    FROM olist_order_items_dataset
),
payment_orders AS (
    SELECT DISTINCT order_id
    FROM olist_order_payments_dataset
)
SELECT
    o.order_status,
    COUNT(*) AS total_orders,
    SUM(i.order_id IS NULL) AS orders_without_items,
    SUM(p.order_id IS NULL) AS orders_without_payments
FROM olist_orders_dataset o
LEFT JOIN item_orders i
    ON o.order_id = i.order_id
LEFT JOIN payment_orders p
    ON o.order_id = p.order_id
GROUP BY o.order_status
ORDER BY o.order_status;


-- =====================================================
-- D. PAYMENT VALUE PROFILE
-- =====================================================
-- PURPOSE:
-- Profile payment records by checking for NULL, negative, zero,
-- and positive payment values.
--
-- KEY METRICS:
-- payment_rows: Total number of payment records.
-- null_values: Records where payment_value is NULL.
-- negative_values: Records with payment_value below zero.
-- zero_values: Records with payment_value equal to zero.
-- positive_values: Records with payment_value above zero.
-- total_payment_value: Sum of recorded payment values, rounded
-- to two decimal places.
--
-- INTERPRETATION:
-- Unexpected values should be investigated in the context of the
-- source data and business rules.

SELECT
    COUNT(*) AS payment_rows,
    SUM(payment_value IS NULL) AS null_values,
    SUM(payment_value < 0) AS negative_values,
    SUM(payment_value = 0) AS zero_values,
    SUM(payment_value > 0) AS positive_values,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM olist_order_payments_dataset;


-- =====================================================
-- E. REVIEW GRAIN
-- =====================================================
-- PURPOSE:
-- Examine review-table volume, identifier uniqueness, order coverage,
-- and review-score validity.
--
-- KEY METRICS:
-- review_rows: Total review records.
-- distinct_review_ids: Number of distinct non-NULL review identifiers.
-- distinct_review_order_pairs: Number of distinct non-NULL
-- review_id/order_id combinations.
-- distinct_reviewed_orders: Number of distinct non-NULL order IDs.
-- null_scores: Records without a review score.
-- invalid_scores: Non-NULL scores outside the range 1 through 5.
--
-- ANALYTICAL NOTE:
-- Comparing row counts with distinct identifier counts helps reveal
-- repeated identifiers or multiple records associated with an order.
-- COUNT(DISTINCT review_id, order_id) excludes combinations where
-- either expression is NULL.

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT review_id) AS distinct_review_ids,
    COUNT(DISTINCT review_id, order_id)
        AS distinct_review_order_pairs,
    COUNT(DISTINCT order_id) AS distinct_reviewed_orders,
    SUM(review_score IS NULL) AS null_scores,
    SUM(review_score NOT BETWEEN 1 AND 5)
        AS invalid_scores
FROM olist_order_reviews_dataset;


-- =====================================================
-- F. DATE VIOLATIONS EXCLUDING ZERO DATES
-- =====================================================
-- PURPOSE:
-- Count timestamp-ordering violations while excluding dates at
-- or below the specified sentinel boundary of '1000-01-01'.
--
-- VALIDATION CHECKS:
-- approval_before_purchase:
--     Approval timestamp occurs before purchase timestamp.
-- delivery_before_carrier:
--     Customer delivery timestamp occurs before carrier delivery.
-- delivery_before_purchase:
--     Customer delivery timestamp occurs before purchase.
--
-- INTERPRETATION:
-- These conditions identify chronology anomalies among records that
-- pass the specified date guards. They do not independently establish
-- why a timestamp is invalid.

SELECT
    SUM(
        order_approved_at < order_purchase_timestamp
        AND order_approved_at > '1000-01-01'
        AND order_purchase_timestamp > '1000-01-01'
    ) AS approval_before_purchase,

    SUM(
        order_delivered_customer_date
            < order_delivered_carrier_date
        AND order_delivered_customer_date > '1000-01-01'
        AND order_delivered_carrier_date > '1000-01-01'
    ) AS delivery_before_carrier,

    SUM(
        order_delivered_customer_date
            < order_purchase_timestamp
        AND order_delivered_customer_date > '1000-01-01'
        AND order_purchase_timestamp > '1000-01-01'
    ) AS delivery_before_purchase
FROM olist_orders_dataset;


-- =====================================================
-- G. ORDERS WITHOUT ITEM RECORDS
-- =====================================================
-- PURPOSE:
-- Retrieve individual orders that have no matching item records.
--
-- LEFT JOIN retains every order, including orders without item rows.
-- The NULL filter selects orders for which no item match exists.
-- Order status and timestamps provide context for further investigation.
--
-- ORDER BY groups results by status and then purchase timestamp.

-- Orders without item records
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_customer_date
FROM olist_orders_dataset o
LEFT JOIN olist_order_items_dataset i
    ON o.order_id = i.order_id
WHERE i.order_id IS NULL
ORDER BY o.order_status, o.order_purchase_timestamp;


-- =====================================================
-- H. ORDERS WITHOUT PAYMENT RECORDS
-- =====================================================
-- PURPOSE:
-- Retrieve individual orders with no associated payment record.
--
-- LEFT JOIN preserves orders without matching payments.
-- The NULL filter identifies those missing payment relationships.
-- Order status and timestamps support contextual investigation.

-- Orders without payment records
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date
FROM olist_orders_dataset o
LEFT JOIN olist_order_payments_dataset p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL;


-- =====================================================
-- I. ORDERS WITHOUT ITEMS: STATUS AND ZERO-DATE PROFILE
-- =====================================================
-- PURPOSE:
-- Group orders without item records by order status and count
-- records with zero approval or delivery timestamps.
--
-- NOT EXISTS checks for the absence of a matching item record.
-- DATE_FORMAT converts each timestamp to the specified string format
-- before comparison with the zero-date representation.
--
-- KEY METRICS:
-- orders_without_items: Number of qualifying orders per status.
-- zero_approval_dates: Qualifying orders with a zero approval date.
-- zero_delivery_dates: Qualifying orders with a zero delivery date.
--
-- This analysis helps investigate whether missing item relationships
-- coincide with incomplete timestamp information.

SELECT
    order_status,
    COUNT(*) AS orders_without_items,
    SUM(
        DATE_FORMAT(order_approved_at, '%Y-%m-%d %H:%i:%s')
        = '0000-00-00 00:00:00'
    ) AS zero_approval_dates,
    SUM(
        DATE_FORMAT(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s')
        = '0000-00-00 00:00:00'
    ) AS zero_delivery_dates
FROM olist_orders_dataset o
WHERE NOT EXISTS (
    SELECT 1
    FROM olist_order_items_dataset i
    WHERE i.order_id = o.order_id
)
GROUP BY order_status
ORDER BY orders_without_items DESC;



-- =====================================================
-- J. INVESTIGATE DELIVERED ORDERS WITHOUT PAYMENTS
-- =====================================================
-- PURPOSE:
-- Inspect item and payment fields for delivered orders that have
-- no matching payment records.
--
-- NOT EXISTS identifies orders with no payment rows.
-- LEFT JOIN retains such orders and their item records.
-- Because no payment record exists, payment-side fields will be NULL.
--
-- NOTE:
-- An order with multiple item records may appear multiple times.
-- This query provides record-level detail rather than one row per order.

SELECT
    o.order_id,
    o.order_status,
    i.order_id AS item_order_id,
    i.price,
    i.freight_value,
    p.order_id AS payment_order_id,
    p.payment_value
FROM olist_orders_dataset o
LEFT JOIN olist_order_items_dataset i
    ON o.order_id = i.order_id
LEFT JOIN olist_order_payments_dataset p
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND NOT EXISTS (
      SELECT 1
      FROM olist_order_payments_dataset p2
      WHERE p2.order_id = o.order_id
  );


-- =====================================================
-- K. SUMMARIZE DELIVERED ORDERS WITHOUT PAYMENTS
-- =====================================================
-- PURPOSE:
-- Produce one result row per delivered order without payment records,
-- including item counts and aggregated item and freight values.
--
-- CORRELATED SUBQUERIES:
-- item_count: Number of item records associated with the order.
-- total_item_value: Sum of item prices, rounded to two decimals.
-- total_freight_value: Sum of freight charges, rounded to two decimals.
-- payment_count: Number of associated payment records.
--
-- NOT EXISTS restricts the results to delivered orders without payments.
-- This summary helps assess the scale and potential financial value
-- associated with missing payment records.

SELECT
    o.order_id,
    o.order_status,

    (
        SELECT COUNT(*)
        FROM olist_order_items_dataset i
        WHERE i.order_id = o.order_id
    ) AS item_count,

    (
        SELECT ROUND(SUM(i.price), 2)
        FROM olist_order_items_dataset i
        WHERE i.order_id = o.order_id
    ) AS total_item_value,

    (
        SELECT ROUND(SUM(i.freight_value), 2)
        FROM olist_order_items_dataset i
        WHERE i.order_id = o.order_id
    ) AS total_freight_value,

    (
        SELECT COUNT(*)
        FROM olist_order_payments_dataset p
        WHERE p.order_id = o.order_id
    ) AS payment_count

FROM olist_orders_dataset o
WHERE o.order_status = 'delivered'
  AND NOT EXISTS (
      SELECT 1
      FROM olist_order_payments_dataset p
      WHERE p.order_id = o.order_id
  );