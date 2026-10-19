-- ============================================================
-- PROJECT: MySQL Analytics Intelligence & Business Performance
--          Control Framework
-- MODULE: M01 - Data Import, Database Setup and Initial Validation
-- DATABASE: olist_analytics
--
-- OBJECTIVE:
-- Establish the analytical database, import the Olist source
-- datasets, and perform initial checks on data volume, schema
-- structure, identifier uniqueness, and missing identifiers.
--
-- NOTE:
-- This module prepares the source data for subsequent data
-- quality checks, analytical views, KPI calculations, and
-- business performance analysis.
-- ============================================================


-- ============================================================
-- SECTION 1: ENABLE AND VERIFY LOCAL DATA IMPORT
-- PURPOSE:
-- Enable local file loading at the MySQL server level and
-- verify the server and current session settings.
-- ============================================================

SET GLOBAL local_infile = 1;

USE olist_analytics;

SHOW GLOBAL VARIABLES LIKE 'local_infile';

SHOW SESSION VARIABLES LIKE 'local_infile';


-- ============================================================
-- SECTION 2: IMPORT CUSTOMER DATA
-- PURPOSE:
-- Load customer identifiers and geographic attributes into
-- the customer source table.
--
-- IMPORT CONFIGURATION:
-- - UTF-8 character encoding supports multilingual text.
-- - Commas separate fields, and double quotes can enclose fields.
-- - The header row is skipped during import.
-- ============================================================

USE olist_analytics;

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_customers_dataset.csv'
INTO TABLE olist_customers_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
);


-- ============================================================
-- SECTION 3: CREATE AND IMPORT ORDER DATA
-- PURPOSE:
-- Define the order-level source table and import order status,
-- customer references, purchase timestamps, approval timestamps,
-- delivery timestamps, and estimated delivery dates.
--
-- DATETIME columns support subsequent delivery-duration,
-- delivery-performance, and order-lifecycle analysis.
-- ============================================================

USE olist_analytics;

CREATE TABLE IF NOT EXISTS olist_orders_dataset (
    order_id VARCHAR(32),
    customer_id VARCHAR(32),
    order_status VARCHAR(20),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME NULL,
    order_delivered_carrier_date DATETIME NULL,
    order_delivered_customer_date DATETIME NULL,
    order_estimated_delivery_date DATETIME
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_orders_dataset.csv'
INTO TABLE olist_orders_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
);

-- Verify the number of records stored in the order table.
SELECT COUNT(*) AS imported_rows
FROM olist_orders_dataset;


-- ============================================================
-- SECTION 4: CREATE AND IMPORT ORDER-ITEM DATA
-- PURPOSE:
-- Store item-level order details, including product and seller
-- references, shipping deadlines, item prices, and freight costs.
--
-- ANALYTICAL USE:
-- Supports merchandise value calculations, freight analysis,
-- product-category performance, and seller-level comparisons.
-- ============================================================

CREATE TABLE IF NOT EXISTS olist_order_items_dataset (
    order_id VARCHAR(32),
    order_item_id INT,
    product_id VARCHAR(32),
    seller_id VARCHAR(32),
    shipping_limit_date DATETIME,
    price DECIMAL(12,2),
    freight_value DECIMAL(12,2)
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_order_items_dataset.csv'
INTO TABLE olist_order_items_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
);

-- Confirm the number of imported order-item records.
SELECT COUNT(*) FROM olist_order_items_dataset;


-- =====================================================
-- . ORDER ITEMS
-- =====================================================

CREATE TABLE IF NOT EXISTS olist_order_items_dataset (
    order_id VARCHAR(32),
    order_item_id INT,
    product_id VARCHAR(32),
    seller_id VARCHAR(32),
    shipping_limit_date DATETIME,
    price DECIMAL(12,2),
    freight_value DECIMAL(12,2)
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_order_items_dataset.csv'
INTO TABLE olist_order_items_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
);


-- ============================================================
-- SECTION 5: CREATE AND IMPORT PAYMENT DATA
-- PURPOSE:
-- Capture payment methods, payment sequence, installment count,
-- and payment values associated with orders.
--
-- ANALYTICAL USE:
-- Supports payment-method comparisons, payment aggregation,
-- installment analysis, and payment reconciliation.
-- ============================================================

-- ============================================================
-- 2. ORDER PAYMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS olist_order_payments_dataset (
    order_id VARCHAR(32),
    payment_sequential INT,
    payment_type VARCHAR(30),
    payment_installments INT,
    payment_value DECIMAL(12,2)
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_order_payments_dataset.csv'
INTO TABLE olist_order_payments_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
);


-- ============================================================
-- SECTION 6: CREATE AND IMPORT ORDER-REVIEW DATA
-- PURPOSE:
-- Store customer review scores and review-related text and
-- timestamps.
--
-- ANALYTICAL USE:
-- Supports customer satisfaction analysis and investigation
-- of relationships between delivery performance and reviews.
-- ============================================================

-- ============================================================
-- 3. ORDER REVIEWS
-- ============================================================

CREATE TABLE IF NOT EXISTS olist_order_reviews_dataset (
    review_id VARCHAR(32),
    order_id VARCHAR(32),
    review_score INT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_order_reviews_dataset.csv'
INTO TABLE olist_order_reviews_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
);

-- Verify the number of imported review records.
SELECT COUNT(*) FROM olist_order_reviews_dataset;


-- ============================================================
-- SECTION 7: CREATE AND IMPORT PRODUCT DATA
-- PURPOSE:
-- Store product identifiers, category information, and product
-- attributes such as dimensions, weight, description length,
-- and photo count.
--
-- ANALYTICAL USE:
-- Supports product-category performance analysis and provides
-- descriptive attributes for further product-level analysis.
-- ============================================================

-- ============================================================
-- 4. PRODUCTS
-- ============================================================

CREATE TABLE IF NOT EXISTS olist_products_dataset (
    product_id VARCHAR(32),
    product_category_name VARCHAR(100),
    product_name_length INT,
    product_description_length INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_products_dataset.csv'
INTO TABLE olist_products_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
);

-- Verify the number of imported product records.
SELECT COUNT(*) FROM olist_products_dataset;


-- ============================================================
-- SECTION 8: CREATE AND IMPORT SELLER DATA
-- PURPOSE:
-- Store seller identifiers and geographic attributes.
--
-- ANALYTICAL USE:
-- Supports seller-level performance comparisons and analysis
-- of seller distribution across cities and states.
-- ============================================================

-- ============================================================
-- 5. SELLERS
-- ============================================================

CREATE TABLE IF NOT EXISTS olist_sellers_dataset (
    seller_id VARCHAR(32),
    seller_zip_code_prefix VARCHAR(5),
    seller_city VARCHAR(100),
    seller_state CHAR(2)
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_sellers_dataset.csv'
INTO TABLE olist_sellers_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
);


-- ============================================================
-- SECTION 9: CREATE AND IMPORT GEOLOCATION DATA
-- PURPOSE:
-- Store geographic coordinates and location attributes
-- associated with postal-code prefixes.
--
-- ANALYTICAL USE:
-- Provides geographic reference data for potential spatial
-- analysis and location-based reporting.
-- ============================================================

-- ============================================================
-- 6. GEOLOCATION
-- ============================================================

CREATE TABLE IF NOT EXISTS olist_geolocation_dataset (
    geolocation_zip_code_prefix VARCHAR(5),
    geolocation_lat DECIMAL(12,8),
    geolocation_lng DECIMAL(12,8),
    geolocation_city VARCHAR(100),
    geolocation_state CHAR(2)
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/olist_geolocation_dataset.csv'
INTO TABLE olist_geolocation_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
);

-- Verify the number of imported geolocation records.
SELECT COUNT(*) FROM olist_geolocation_dataset;


-- ============================================================
-- SECTION 10: IMPORT PRODUCT-CATEGORY TRANSLATIONS
-- PURPOSE:
-- Load the mapping between original product-category names
-- and their English equivalents.
--
-- ANALYTICAL USE:
-- Improves category readability in reports and analysis
-- when English category labels are required.
-- ============================================================

-- ============================================================
-- 7. PRODUCT CATEGORY TRANSLATION
-- ============================================================

CREATE TABLE IF NOT EXISTS product_category_name_translation (
    product_category_name VARCHAR(100),
    product_category_name_english VARCHAR(100)
);

LOAD DATA LOCAL INFILE
'D:/olist_project_analysis/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    product_category_name,
    product_category_name_english
);


-- ============================================================
-- SECTION 11: VERIFY IMPORTED ROW COUNTS
-- PURPOSE:
-- Compare the number of records across the imported source
-- tables to establish a basic inventory of dataset coverage.
--
-- INTERPRETATION:
-- Row counts confirm the volume currently stored in each table.
-- They do not, by themselves, establish data completeness
-- or correctness.
-- ============================================================

-- ------------------------------------ Verification ----------------------------

SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM olist_customers_dataset
UNION ALL
SELECT 'orders', COUNT(*) FROM olist_orders_dataset
UNION ALL
SELECT 'order_items', COUNT(*) FROM olist_order_items_dataset
UNION ALL
SELECT 'order_payments', COUNT(*) FROM olist_order_payments_dataset
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM olist_order_reviews_dataset
UNION ALL
SELECT 'products', COUNT(*) FROM olist_products_dataset
UNION ALL
SELECT 'sellers', COUNT(*) FROM olist_sellers_dataset
UNION ALL
SELECT 'geolocation', COUNT(*) FROM olist_geolocation_dataset
UNION ALL
SELECT 'category_translation',COUNT(*) FROM product_category_name_translation;


-- ============================================================
-- SECTION 12: VERIFY DATABASE AND MYSQL VERSION
-- PURPOSE:
-- Record the active database and MySQL version for environment
-- verification and project reproducibility.
-- ============================================================

SELECT VERSION() AS mysql_version,
       DATABASE() AS active_database;


-- ============================================================
-- SECTION 13: INSPECT TABLE SCHEMAS
-- PURPOSE:
-- Review column names, data types, nullability, and key metadata
-- for the tables in the analytical database.
--
-- ANALYTICAL USE:
-- Confirms the imported schema and helps identify structural
-- characteristics needed for later joins and validation rules.
-- ============================================================

SELECT
    table_name,
    column_name,
    column_type,
    is_nullable,
    column_key
FROM information_schema.columns
WHERE table_schema = 'olist_analytics'
ORDER BY table_name, ordinal_position;


-- ============================================================
-- SECTION 14: CHECK CUSTOMER IDENTIFIER QUALITY
-- PURPOSE:
-- Measure customer table row count, distinct customer IDs,
-- and rows with missing customer IDs.
--
-- INTERPRETATION:
-- Differences between total and distinct counts can indicate
-- repeated identifiers. NULL counts highlight missing IDs.
-- ============================================================

USE olist_analytics;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    SUM(customer_id IS NULL) AS null_customer_ids
FROM olist_customers_dataset;


-- ============================================================
-- SECTION 15: CHECK ORDER IDENTIFIER QUALITY
-- PURPOSE:
-- Measure total order rows, distinct order IDs, and missing
-- order identifiers.
--
-- ANALYTICAL USE:
-- Establishes a baseline for subsequent order-level validation.
-- ============================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    SUM(order_id IS NULL) AS null_order_ids
FROM olist_orders_dataset;


-- ============================================================
-- SECTION 16: CHECK PRODUCT IDENTIFIER QUALITY
-- PURPOSE:
-- Measure product table volume, distinct product IDs, and
-- missing product identifiers.
--
-- ANALYTICAL USE:
-- Provides a baseline for product-level joins and validation.
-- ============================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id) AS distinct_product_ids,
    SUM(product_id IS NULL) AS null_product_ids
FROM olist_products_dataset;


-- ============================================================
-- SECTION 17: CHECK SELLER IDENTIFIER QUALITY
-- PURPOSE:
-- Measure seller table volume, distinct seller IDs, and
-- missing seller identifiers.
--
-- ANALYTICAL USE:
-- Provides a baseline for seller-level joins and analysis.
-- ============================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT seller_id) AS distinct_seller_ids,
    SUM(seller_id IS NULL) AS null_seller_ids
FROM olist_sellers_dataset;


-- ============================================================
-- SECTION 18: CONSOLIDATED ENTITY IDENTIFIER CHECK
-- PURPOSE:
-- Present basic identifier-quality metrics for customers,
-- orders, and products in a single result set.
--
-- BENEFIT:
-- Makes initial comparisons easier by returning the selected
-- entity checks in a consistent table format.
-- ============================================================

USE olist_analytics;

-- 1. Customers
SELECT
    'customers' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_ids,
    SUM(customer_id IS NULL) AS null_ids
FROM olist_customers_dataset

UNION ALL

-- 2. Orders
SELECT
    'orders',
    COUNT(*),
    COUNT(DISTINCT order_id),
    SUM(order_id IS NULL)
FROM olist_orders_dataset

UNION ALL

-- 3. Products
SELECT
    'products',
    COUNT(*),
    COUNT(DISTINCT product_id),
    SUM(product_id IS NULL)
FROM olist_products_dataset;


-- ============================================================
-- SECTION 19: CHECK ORDER-ITEM IDENTIFIER QUALITY
-- PURPOSE:
-- Measure total order-item rows, distinct combinations of
-- order_id and order_item_id, and missing identifier values.
--
-- INTERPRETATION:
-- The composite identifier check evaluates uniqueness at the
-- order-item level rather than using order_id alone, because
-- an order can contain multiple items.
-- ============================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id, order_item_id) AS distinct_order_items,
    SUM(order_id IS NULL) AS null_order_ids,
    SUM(order_item_id IS NULL) AS null_item_ids
FROM olist_order_items_dataset;