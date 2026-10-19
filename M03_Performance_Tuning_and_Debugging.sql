-- ============================================================
-- SECTION 1: QUERY MONITORING AND PROCEDURE INSPECTION
-- ============================================================

-- Stop the currently executing query associated with process ID 16.
-- CAUTION: Confirm the process ID belongs to the query you intend to stop.
KILL QUERY 16;

-- Inspect active connections and running queries.
-- Useful for identifying long-running statements and blocked sessions.
SHOW FULL PROCESSLIST;

-- Inspect the stored procedure definition.
-- This helps verify the current implementation of the data-quality framework.
SHOW CREATE PROCEDURE olist_analytics.sp_run_data_quality_checks;


-- ============================================================
-- SECTION 2: EXISTING INDEX INSPECTION
-- ============================================================

-- Inspect indexes on the orders table.
SHOW INDEX FROM olist_orders_dataset;

-- Inspect indexes on the order-items table.
SHOW INDEX FROM olist_order_items_dataset;

-- Inspect indexes on the order-payments table.
SHOW INDEX FROM olist_order_payments_dataset;

-- Inspect indexes on the order-reviews table.
SHOW INDEX FROM olist_order_reviews_dataset;


-- Inspect the stored procedure definition again.
-- This is a repeated diagnostic statement from the original script.
SHOW CREATE PROCEDURE olist_analytics.sp_run_data_quality_checks;


-- ============================================================
-- SECTION 3: DATABASE AND TABLE INVENTORY
-- ============================================================

-- Set the active database for subsequent unqualified object references.
USE olist_analytics;

-- List all tables in the active database.
SHOW TABLES;

-- Retrieve index metadata for the four source tables.
-- NON_UNIQUE = 0 indicates a unique index.
-- NON_UNIQUE = 1 indicates a non-unique index.
-- SEQ_IN_INDEX identifies each column's position within a composite index.
SELECT
    TABLE_NAME,
    INDEX_NAME,
    COLUMN_NAME,
    NON_UNIQUE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'olist_analytics'
  AND TABLE_NAME IN (
      'olist_orders_dataset',
      'olist_order_items_dataset',
      'olist_order_payments_dataset',
      'olist_order_reviews_dataset'
  )
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;

-- Confirm that the four expected source tables exist.
-- The result should report 4 if all four tables are present.
SELECT
    DATABASE() AS current_database,
    COUNT(*) AS tables_found
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'olist_analytics'
  AND TABLE_NAME IN (
      'olist_orders_dataset',
      'olist_order_items_dataset',
      'olist_order_payments_dataset',
      'olist_order_reviews_dataset'
  );


-- ============================================================
-- SECTION 4: SOURCE TABLE STRUCTURE AND INDEX DETAILS
-- ============================================================

-- Inspect the orders table definition, including columns and indexes.
SHOW CREATE TABLE olist_orders_dataset;

-- Inspect existing indexes on the orders table.
SHOW INDEX FROM olist_analytics.olist_orders_dataset;

-- Inspect existing indexes on the order-items table.
SHOW INDEX FROM olist_analytics.olist_order_items_dataset;

-- Inspect existing indexes on the order-payments table.
SHOW INDEX FROM olist_analytics.olist_order_payments_dataset;

-- Inspect existing indexes on the order-reviews table.
SHOW INDEX FROM olist_analytics.olist_order_reviews_dataset;


-- ============================================================
-- SECTION 5: INDEX CREATION FOR RELATIONSHIP VALIDATION
-- ============================================================

-- Ensure subsequent unqualified table references use olist_analytics.
USE olist_analytics;

-- Create an index on the order identifier.
-- This can improve joins and lookups involving the orders table.
-- If the index already exists, this statement will return an error.
CREATE INDEX idx_orders_order_id
    ON olist_orders_dataset (order_id);

-- Index order identifiers in the order-items table.
-- Useful for order-level aggregation and orphan-record checks.
CREATE INDEX idx_order_items_order_id
    ON olist_order_items_dataset (order_id);

-- Index order identifiers in the order-payments table.
-- Useful for payment-to-order matching and reconciliation.
CREATE INDEX idx_order_payments_order_id
    ON olist_order_payments_dataset (order_id);

-- Create a composite index for review and order identifiers.
-- Useful for queries that filter or group by these columns together.
CREATE INDEX idx_order_reviews_review_order
    ON olist_order_reviews_dataset (review_id, order_id);


-- ============================================================
-- SECTION 6: VERIFY INDEX CREATION
-- ============================================================

-- Confirm the indexes currently present on each source table.
SHOW INDEX FROM olist_orders_dataset;

SHOW INDEX FROM olist_order_items_dataset;

SHOW INDEX FROM olist_order_payments_dataset;

SHOW INDEX FROM olist_order_reviews_dataset;


-- ============================================================
-- SECTION 7: CHECK SERVER ACTIVITY AND EXECUTE VALIDATION
-- ============================================================

-- Inspect current database sessions before running the procedure.
SHOW FULL PROCESSLIST;

-- Execute the data-quality validation procedure.
-- This writes validation-run, rule-result, and issue-detail records.
-- The procedure may fail if a rule violates a table constraint.
CALL olist_analytics.sp_run_data_quality_checks();

-- Inspect the most recently recorded validation run.
-- Review run status, timestamps, and any available error message.
SELECT *
FROM olist_analytics.dq_validation_runs
ORDER BY run_id DESC
LIMIT 1;


-- ============================================================
-- SECTION 8: SUMMARIZE RULE RESULTS FOR RUN 2
-- ============================================================

-- Count recorded rule-result rows by rule name and severity.
-- This query summarizes the aggregate rule results, not individual issues.
SELECT
    rule_name,
    severity,
    COUNT(*) AS issue_count
FROM olist_analytics.dq_rule_results
WHERE run_id = 2
GROUP BY rule_name, severity
ORDER BY issue_count DESC;

-- Inspect the structure of the rule-results table.
-- Useful for checking column names, data types, and nullability.
DESCRIBE olist_analytics.dq_rule_results;

-- Review evaluated rows, failed rows, and stored pass percentages.
-- Ordering by failed_rows puts the highest failure counts first.
SELECT
    rule_code,
    evaluated_rows,
    failed_rows,
    pass_percentage
FROM olist_analytics.dq_rule_results
WHERE run_id = 2
ORDER BY failed_rows DESC;


-- ============================================================
-- SECTION 9: INSPECT THE RULE CATALOG AND REGISTRY
-- ============================================================

-- Inspect the rule catalog, if this table exists in the database.
SELECT *
FROM olist_analytics.dq_rule_catalog;

-- List all tables in the analytics database.
SHOW TABLES FROM olist_analytics;

-- Inspect registered data-quality rules, including their configuration.
SELECT *
FROM olist_analytics.dq_rule_registry;


-- ============================================================
-- SECTION 10: CALCULATE PASS PERCENTAGES FOR RUN 2
-- ============================================================

-- Calculate pass percentages independently from the stored values.
-- Formula: (evaluated_rows - failed_rows) / evaluated_rows * 100.
-- NULLIF prevents division by zero.
-- This is a diagnostic calculation; it does not update stored results.
SELECT
    r.rule_code,
    r.rule_name,
    d.evaluated_rows,
    d.failed_rows,
    ROUND(
        100.0 * (d.evaluated_rows - d.failed_rows)
        / NULLIF(d.evaluated_rows, 0),
        2
    ) AS calculated_pass_percentage
FROM olist_analytics.dq_rule_results d
JOIN olist_analytics.dq_rule_registry r
    ON d.rule_code = r.rule_code
WHERE d.run_id = 2
ORDER BY d.failed_rows DESC;


-- ============================================================
-- SECTION 11: UPDATE STORED PASS PERCENTAGES FOR RUN 2
-- ============================================================

-- Set the active database.
USE olist_analytics;

-- Update the stored pass percentage for existing results in run 2.
-- CAUTION: This modifies database records.
-- Rows with evaluated_rows = 0 receive NULL because of NULLIF.
-- The calculation assumes failed_rows does not exceed evaluated_rows.
UPDATE dq_rule_results
SET pass_percentage = ROUND(
    100.0 * (evaluated_rows - failed_rows)
    / NULLIF(evaluated_rows, 0),
    2
)
WHERE run_id = 2;

-- Verify the stored pass percentages after the update.
SELECT
    rule_code,
    evaluated_rows,
    failed_rows,
    pass_percentage
FROM olist_analytics.dq_rule_results
WHERE run_id = 2
ORDER BY failed_rows DESC;


-- ============================================================
-- SECTION 12: REINSPECT THE PROCEDURE
-- ============================================================

-- Inspect the procedure definition before introducing the trigger.
SHOW CREATE PROCEDURE olist_analytics.sp_run_data_quality_checks;


-- ============================================================
-- SECTION 13: CREATE A PASS-PERCENTAGE TRIGGER
-- ============================================================

-- Set the active database.
USE olist_analytics;

-- Remove the trigger if it already exists.
-- This drops the trigger definition; it does not delete table records.
DROP TRIGGER IF EXISTS trg_dq_calculate_pass_percentage;

-- Change the statement delimiter so the trigger's internal semicolons
-- are not interpreted as the end of the CREATE TRIGGER statement.
DELIMITER $$

-- Automatically calculate pass_percentage before each new rule-result row
-- is inserted into dq_rule_results.
-- When evaluated_rows is NULL or zero, pass_percentage is set to NULL.
-- Otherwise, the trigger calculates the percentage using the supplied
-- evaluated_rows and failed_rows values.
CREATE TRIGGER trg_dq_calculate_pass_percentage
BEFORE INSERT ON dq_rule_results
FOR EACH ROW
BEGIN
    SET NEW.pass_percentage =
        CASE
            WHEN NEW.evaluated_rows IS NULL
                 OR NEW.evaluated_rows = 0
            THEN NULL
            ELSE ROUND(
                100.0 * (NEW.evaluated_rows - NEW.failed_rows)
                / NEW.evaluated_rows,
                2
            )
        END;
END$$

-- Restore the default statement delimiter.
DELIMITER ;

-- Verify that the trigger exists and inspect its metadata.
SHOW TRIGGERS FROM olist_analytics
LIKE 'dq_rule_results';