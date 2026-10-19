USE olist_analytics;

-- =========================================================
-- M03.1: VALIDATION RULE REGISTRY
-- =========================================================
-- PURPOSE:
-- Create a central registry containing the data-quality rules
-- supported by the validation framework.
--
-- DESIGN:
-- rule_code uniquely identifies each validation rule.
-- rule_name provides a readable rule title.
-- source_table identifies the primary table being validated.
-- severity defines the operational importance of an issue.
-- rule_description explains the condition being investigated.
-- denominator_definition documents the population used to interpret
-- the rule's results.
-- is_active controls whether a rule is evaluated by the procedure.
-- created_at records when the rule was registered.
--
-- The CHECK constraint restricts severity to the four permitted
-- categories, helping maintain consistent issue classification.

CREATE TABLE IF NOT EXISTS dq_rule_registry (
    rule_code VARCHAR(60) PRIMARY KEY,
    rule_name VARCHAR(150) NOT NULL,
    source_table VARCHAR(100) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    rule_description VARCHAR(500) NOT NULL,
    denominator_definition VARCHAR(300) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_dq_rule_severity
        CHECK (severity IN ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW'))
);


-- =========================================================
-- M03.2: VALIDATION RUN HISTORY
-- =========================================================
-- PURPOSE:
-- Maintain one history record for each execution of the
-- data-quality validation procedure.
--
-- DESIGN:
-- run_id uniquely identifies each execution.
-- started_at records when the run begins.
-- completed_at records when the run finishes.
-- run_status tracks whether execution is running, completed,
-- or failed.
-- total_rules_evaluated stores the number of rule-result records.
-- total_issues stores the recorded aggregate of failed rows.
-- quality_score stores the calculated quality percentage.
-- error_message stores diagnostic context if execution fails.
--
-- The status CHECK constraint limits run_status to the supported
-- execution states.

CREATE TABLE IF NOT EXISTS dq_validation_runs (
    run_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME NULL,
    run_status VARCHAR(20) NOT NULL DEFAULT 'RUNNING',
    total_rules_evaluated INT UNSIGNED NOT NULL DEFAULT 0,
    total_issues BIGINT UNSIGNED NOT NULL DEFAULT 0,
    quality_score DECIMAL(6,2) NULL,
    error_message TEXT NULL,

    CONSTRAINT chk_dq_run_status
        CHECK (
            run_status IN ('RUNNING', 'COMPLETED', 'FAILED')
        )
);


-- =========================================================
-- M03.3: PER-RULE RESULTS
-- =========================================================
-- PURPOSE:
-- Store the outcome of each validation rule for each execution.
--
-- DESIGN:
-- run_id links the result to a validation run.
-- rule_code identifies the evaluated rule.
-- evaluated_rows records the size of the population checked.
-- failed_rows records how many rows violated the rule.
-- pass_percentage provides a field for storing the rule's
-- calculated pass percentage.
--
-- The composite primary key prevents duplicate result records
-- for the same rule within the same run.
--
-- Foreign keys maintain relationships with the run-history and
-- rule-registry tables.
--
-- The CHECK constraint prevents failed_rows from exceeding
-- evaluated_rows.

CREATE TABLE IF NOT EXISTS dq_rule_results (
    run_id BIGINT UNSIGNED NOT NULL,
    rule_code VARCHAR(60) NOT NULL,
    evaluated_rows BIGINT UNSIGNED NOT NULL DEFAULT 0,
    failed_rows BIGINT UNSIGNED NOT NULL DEFAULT 0,
    pass_percentage DECIMAL(6,2) NULL,

    PRIMARY KEY (run_id, rule_code),

    CONSTRAINT fk_dq_result_run
        FOREIGN KEY (run_id)
        REFERENCES dq_validation_runs(run_id),

    CONSTRAINT fk_dq_result_rule
        FOREIGN KEY (rule_code)
        REFERENCES dq_rule_registry(rule_code),

    CONSTRAINT chk_dq_result_counts
        CHECK (failed_rows <= evaluated_rows)
);


-- =========================================================
-- M03.4: INDIVIDUAL ISSUE DETAILS
-- =========================================================
-- PURPOSE:
-- Store row-level details for records identified by validation rules.
--
-- DESIGN:
-- issue_id uniquely identifies an issue record.
-- run_id identifies the execution that detected the issue.
-- rule_code identifies the violated validation rule.
-- entity_table identifies the affected source table.
-- entity_key identifies the affected entity or record.
-- severity classifies the operational importance of the issue.
-- issue_description explains the detected condition.
-- observed_value captures relevant information from the record.
-- expected_condition documents the expected business condition.
-- detected_at records when the issue was logged.
--
-- The unique key prevents the same entity and rule from being
-- recorded more than once within a single validation run.
--
-- Indexes support common investigation patterns:
-- severity-based filtering, rule-based filtering, and entity lookup.
--
-- Foreign keys preserve the relationships with run history and
-- the rule registry. The CHECK constraint validates severity values.

CREATE TABLE IF NOT EXISTS dq_issue_details (
    issue_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    run_id BIGINT UNSIGNED NOT NULL,
    rule_code VARCHAR(60) NOT NULL,
    entity_table VARCHAR(100) NOT NULL,
    entity_key VARCHAR(255) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    issue_description VARCHAR(500) NOT NULL,
    observed_value TEXT NULL,
    expected_condition VARCHAR(500) NOT NULL,
    detected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- One issue per entity and rule within a run.
    UNIQUE KEY uq_dq_issue_per_run (
        run_id, rule_code, entity_key
    ),

    KEY idx_dq_issue_severity (severity),
    KEY idx_dq_issue_rule (rule_code),
    KEY idx_dq_issue_entity (entity_table, entity_key),

    CONSTRAINT fk_dq_issue_run
        FOREIGN KEY (run_id)
        REFERENCES dq_validation_runs(run_id),

    CONSTRAINT fk_dq_issue_rule
        FOREIGN KEY (rule_code)
        REFERENCES dq_rule_registry(rule_code),

    CONSTRAINT chk_dq_issue_severity
        CHECK (
            severity IN ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
        )
);


-- =========================================================
-- M03.5: REGISTER DATA-QUALITY RULES
-- =========================================================
-- PURPOSE:
-- Populate the rule registry with the 12 validation rules
-- implemented by the stored procedure.
--
-- RULE CATEGORIES:
-- Relationship integrity:
--     ORDER_NO_ITEMS
--     DELIVERED_NO_PAYMENT
--     ORPHAN_ITEM_ORDER
--     ORPHAN_PAYMENT_ORDER
--
-- Payment validation:
--     ZERO_PAYMENT
--     NEGATIVE_PAYMENT
--
-- Review validation:
--     INVALID_REVIEW_SCORE
--     DUPLICATE_REVIEW_PAIR
--
-- Timestamp validation:
--     DELIVERED_ZERO_DELIVERY_DATE
--     DELIVERED_ZERO_CARRIER_DATE
--     DELIVERY_BEFORE_CARRIER
--     ZERO_APPROVAL_DATE
--
-- The denominator_definition field documents the intended population
-- for interpreting the corresponding rule's failure count.
--
-- ON DUPLICATE KEY UPDATE makes registry setup repeatable:
-- existing rules are updated rather than causing duplicate-key
-- insertion errors. Fields not listed in the update clause,
-- including is_active and created_at, are not updated by this clause.

INSERT INTO dq_rule_registry (
    rule_code,
    rule_name,
    source_table,
    severity,
    rule_description,
    denominator_definition
)
VALUES
(
    'ORDER_NO_ITEMS',
    'Order has no item records',
    'olist_orders_dataset',
    'MEDIUM',
    'Identifies orders without matching order-item records.',
    'All orders'
),
(
    'DELIVERED_NO_PAYMENT',
    'Delivered order has no payment record',
    'olist_orders_dataset',
    'HIGH',
    'Identifies delivered orders without a matching payment record.',
    'All delivered orders'
),
(
    'ORPHAN_ITEM_ORDER',
    'Order item references missing order',
    'olist_order_items_dataset',
    'HIGH',
    'Identifies item records without a matching order.',
    'All order-item records'
),
(
    'ORPHAN_PAYMENT_ORDER',
    'Payment references missing order',
    'olist_order_payments_dataset',
    'HIGH',
    'Identifies payment records without a matching order.',
    'All payment records'
),
(
    'ZERO_PAYMENT',
    'Zero-value payment record',
    'olist_order_payments_dataset',
    'LOW',
    'Flags zero-value payments for investigation without assuming they are invalid.',
    'All payment records'
),
(
    'NEGATIVE_PAYMENT',
    'Negative payment value',
    'olist_order_payments_dataset',
    'HIGH',
    'Identifies negative payment values.',
    'All payment records'
),
(
    'INVALID_REVIEW_SCORE',
    'Review score outside permitted range',
    'olist_order_reviews_dataset',
    'HIGH',
    'Identifies non-NULL review scores outside 1 through 5.',
    'All review records'
),
(
    'DUPLICATE_REVIEW_PAIR',
    'Repeated review and order pair',
    'olist_order_reviews_dataset',
    'HIGH',
    'Checks whether the candidate review/order key is repeated.',
    'All review records'
),
(
    'DELIVERED_ZERO_DELIVERY_DATE',
    'Delivered order has zero delivery date',
    'olist_orders_dataset',
    'HIGH',
    'Flags delivered orders whose delivery date is represented by a zero date.',
    'All delivered orders'
),
(
    'DELIVERED_ZERO_CARRIER_DATE',
    'Delivered order has zero carrier date',
    'olist_orders_dataset',
    'MEDIUM',
    'Flags delivered orders with a zero carrier-handoff date.',
    'All delivered orders'
),
(
    'DELIVERY_BEFORE_CARRIER',
    'Delivery precedes carrier handoff',
    'olist_orders_dataset',
    'HIGH',
    'Identifies valid timestamps where customer delivery precedes carrier handoff.',
    'Orders with both timestamps valid'
),
(
    'ZERO_APPROVAL_DATE',
    'Zero approval date on an order expected to be approved',
    'olist_orders_dataset',
    'MEDIUM',
    'Flags zero approval dates for statuses expected to have progressed beyond approval.',
    'Orders in delivered, shipped, invoiced, processing or approved status'
)
ON DUPLICATE KEY UPDATE
    rule_name = VALUES(rule_name),
    source_table = VALUES(source_table),
    severity = VALUES(severity),
    rule_description = VALUES(rule_description),
    denominator_definition = VALUES(denominator_definition);
    
-- =========================================================
-- M03.6: STORED PROCEDURE SETUP
-- =========================================================
-- PURPOSE:
-- Create the stored procedure that executes the registered
-- data-quality validation rules and records their results.
--
-- DROP PROCEDURE IF EXISTS removes an existing version so the
-- procedure can be recreated when the script is rerun.
--
-- DELIMITER $$ temporarily changes the statement terminator.
-- This allows MySQL to interpret the semicolons inside the
-- procedure body without ending the CREATE PROCEDURE statement.

USE olist_analytics;

DROP PROCEDURE IF EXISTS sp_run_data_quality_checks;

DELIMITER $$

CREATE PROCEDURE sp_run_data_quality_checks()
BEGIN

    -- -----------------------------------------------------
    -- 1. DECLARE EXECUTION VARIABLES
    -- -----------------------------------------------------
    -- v_run_id identifies the current validation execution.
    -- v_rules stores the number of rule-result records created.
    -- v_issues stores the sum of failed rows across rule results.
    -- v_score stores the calculated overall quality percentage.

    DECLARE v_run_id BIGINT UNSIGNED;
    DECLARE v_rules INT DEFAULT 0;
    DECLARE v_issues BIGINT DEFAULT 0;
    DECLARE v_score DECIMAL(6,2) DEFAULT NULL;


    -- -----------------------------------------------------
    -- 2. HANDLE SQL EXCEPTIONS
    -- -----------------------------------------------------
    -- PURPOSE:
    -- Define how the procedure responds if a SQL exception occurs.
    --
    -- ROLLBACK attempts to undo transactional changes made by the
    -- current execution.
    --
    -- If a run ID has already been assigned, the corresponding
    -- run-history record is marked FAILED and an error message
    -- is stored.
    --
    -- RESIGNAL propagates the original SQL exception so that
    -- the caller can see the execution failure.

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        IF v_run_id IS NOT NULL THEN
            UPDATE dq_validation_runs
            SET run_status = 'FAILED',
                completed_at = NOW(),
                error_message =
                    'Validation execution failed. Inspect SQL error output.'
            WHERE run_id = v_run_id;
        END IF;

        RESIGNAL;
    END;


    -- -----------------------------------------------------
    -- 3. INITIALIZE AND START THE VALIDATION RUN
    -- -----------------------------------------------------
    -- Reset the run identifier before starting.
    -- Start a transaction so the validation operations can be
    -- committed together if execution succeeds.

    SET v_run_id = NULL;

    START TRANSACTION;

    -- Create a history record for this execution.
    -- The default status is RUNNING.

    INSERT INTO dq_validation_runs (run_status)
    VALUES ('RUNNING');

    -- Capture the automatically generated identifier for this run.

    SET v_run_id = LAST_INSERT_ID();


    -- =====================================================
    -- RULE 1: ORDERS WITHOUT ITEMS
    -- =====================================================
    -- PURPOSE:
    -- Identify orders that have no corresponding item records.
    --
    -- The rule runs only when its registry entry exists and is active.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all orders.
    -- failed_rows counts orders without matching item records.
    --
    -- ISSUE DETAILS:
    -- Store the affected order ID, order status, severity,
    -- observed information, and expected business condition.
    --
    -- Orders in delivered, shipped, or invoiced status are assigned
    -- HIGH severity by this rule; other statuses receive MEDIUM.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'ORDER_NO_ITEMS'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'ORDER_NO_ITEMS',
            COUNT(*),
            SUM(
                NOT EXISTS (
                    SELECT 1
                    FROM olist_order_items_dataset i
                    WHERE i.order_id = o.order_id
                )
            )
        FROM olist_orders_dataset o;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'ORDER_NO_ITEMS',
            'olist_orders_dataset',
            o.order_id,
            CASE
                WHEN o.order_status IN (
                    'delivered', 'shipped', 'invoiced'
                ) THEN 'HIGH'
                ELSE 'MEDIUM'
            END,
            'Order has no matching order-item records.',
            CONCAT('order_status=', o.order_status),
            'An order expected to contain items should have matching item records.'
        FROM olist_orders_dataset o
        WHERE NOT EXISTS (
            SELECT 1
            FROM olist_order_items_dataset i
            WHERE i.order_id = o.order_id
        );

    END IF;


    -- =====================================================
    -- RULE 2: DELIVERED ORDER WITHOUT PAYMENT
    -- =====================================================
    -- PURPOSE:
    -- Identify delivered orders without matching payment records.
    --
    -- RULE RESULT:
    -- evaluated_rows counts delivered orders.
    -- failed_rows counts delivered orders for which no payment
    -- record exists.
    --
    -- ISSUE DETAILS:
    -- Record each affected order as a HIGH-severity issue.
    -- The expected condition documents the selected business rule
    -- that delivered orders should have traceable payment records.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'DELIVERED_NO_PAYMENT'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'DELIVERED_NO_PAYMENT',
            COUNT(*),
            SUM(
                NOT EXISTS (
                    SELECT 1
                    FROM olist_order_payments_dataset p
                    WHERE p.order_id = o.order_id
                )
            )
        FROM olist_orders_dataset o
        WHERE o.order_status = 'delivered';

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'DELIVERED_NO_PAYMENT',
            'olist_orders_dataset',
            o.order_id,
            'HIGH',
            'Delivered order has no matching payment record.',
            CONCAT('order_status=', o.order_status),
            'A delivered order should have a traceable payment record under the selected business rule.'
        FROM olist_orders_dataset o
        WHERE o.order_status = 'delivered'
          AND NOT EXISTS (
              SELECT 1
              FROM olist_order_payments_dataset p
              WHERE p.order_id = o.order_id
          );

    END IF;


    -- =====================================================
    -- RULE 3: ORPHAN ORDER ITEMS
    -- =====================================================
    -- PURPOSE:
    -- Identify order-item records whose order_id does not exist
    -- in the main orders table.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all order-item records.
    -- failed_rows counts item records without a matching order.
    --
    -- ISSUE DETAILS:
    -- The entity key combines order_id and order_item_id to identify
    -- the individual item record being investigated.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'ORPHAN_ITEM_ORDER'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'ORPHAN_ITEM_ORDER',
            COUNT(*),
            SUM(
                NOT EXISTS (
                    SELECT 1
                    FROM olist_orders_dataset o
                    WHERE o.order_id = i.order_id
                )
            )
        FROM olist_order_items_dataset i;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'ORPHAN_ITEM_ORDER',
            'olist_order_items_dataset',
            CONCAT(i.order_id, ':', i.order_item_id),
            'HIGH',
            'Order-item record references a missing order.',
            CONCAT('order_id=', i.order_id),
            'Every item record should reference an existing order.'
        FROM olist_order_items_dataset i
        WHERE NOT EXISTS (
            SELECT 1
            FROM olist_orders_dataset o
            WHERE o.order_id = i.order_id
        );

    END IF;


    -- =====================================================
    -- RULE 4: ORPHAN PAYMENTS
    -- =====================================================
    -- PURPOSE:
    -- Identify payment records whose order_id does not exist
    -- in the main orders table.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all payment records.
    -- failed_rows counts payment records without a matching order.
    --
    -- ISSUE DETAILS:
    -- The entity key combines order_id and payment_sequential
    -- to identify the specific payment record.
    -- Orphan payment records are assigned HIGH severity.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'ORPHAN_PAYMENT_ORDER'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'ORPHAN_PAYMENT_ORDER',
            COUNT(*),
            SUM(
                NOT EXISTS (
                    SELECT 1
                    FROM olist_orders_dataset o
                    WHERE o.order_id = p.order_id
                )
            )
        FROM olist_order_payments_dataset p;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'ORPHAN_PAYMENT_ORDER',
            'olist_order_payments_dataset',
            CONCAT(p.order_id, ':', p.payment_sequential),
            'HIGH',
            'Payment record references a missing order.',
            CONCAT('order_id=', p.order_id),
            'Every payment record should reference an existing order.'
        FROM olist_order_payments_dataset p
        WHERE NOT EXISTS (
            SELECT 1
            FROM olist_orders_dataset o
            WHERE o.order_id = p.order_id
        );

    END IF;
    
    -- =====================================================
    -- RULE 5: ZERO-VALUE PAYMENTS
    -- =====================================================
    -- PURPOSE:
    -- Identify payment records where payment_value equals zero.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all payment records.
    -- failed_rows counts records with a zero payment value.
    --
    -- ISSUE DETAILS:
    -- Record the order ID, payment sequence, payment type,
    -- and observed payment value for investigation.
    --
    -- Zero-value payments are classified as LOW severity.
    -- A zero amount is flagged for review, not automatically
    -- treated as invalid.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'ZERO_PAYMENT'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'ZERO_PAYMENT',
            COUNT(*),
            SUM(payment_value = 0)
        FROM olist_order_payments_dataset;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'ZERO_PAYMENT',
            'olist_order_payments_dataset',
            CONCAT(p.order_id, ':', p.payment_sequential),
            'LOW',
            'Zero-value payment requires review.',
            CONCAT(
                'payment_type=', p.payment_type,
                '; payment_value=', p.payment_value
            ),
            'Investigate zero-value payments; zero does not automatically mean invalid.'
        FROM olist_order_payments_dataset p
        WHERE p.payment_value = 0;

    END IF;


    -- =====================================================
    -- RULE 6: NEGATIVE PAYMENTS
    -- =====================================================
    -- PURPOSE:
    -- Identify payment records with payment_value below zero.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all payment records.
    -- failed_rows counts records with negative payment values.
    --
    -- ISSUE DETAILS:
    -- Store the payment identifier and observed negative amount.
    -- Negative payments are assigned HIGH severity for investigation.
    --
    -- A negative value should be checked against source records and
    -- the applicable financial definition before being classified
    -- as an actual data error.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'NEGATIVE_PAYMENT'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'NEGATIVE_PAYMENT',
            COUNT(*),
            SUM(payment_value < 0)
        FROM olist_order_payments_dataset;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'NEGATIVE_PAYMENT',
            'olist_order_payments_dataset',
            CONCAT(p.order_id, ':', p.payment_sequential),
            'HIGH',
            'Negative payment value detected.',
            CAST(p.payment_value AS CHAR),
            'Investigate negative payment amounts against the source and financial definition.'
        FROM olist_order_payments_dataset p
        WHERE p.payment_value < 0;

    END IF;


    -- =====================================================
    -- RULE 7: INVALID REVIEW SCORES
    -- =====================================================
    -- PURPOSE:
    -- Identify non-NULL review scores outside the permitted
    -- range of 1 through 5.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all review records.
    -- failed_rows counts non-NULL scores outside the permitted range.
    --
    -- ISSUE DETAILS:
    -- Store the review/order identifier pair and observed score.
    -- Invalid review scores are classified as HIGH severity.
    --
    -- NULL scores are excluded from this rule's failure condition;
    -- this rule does not evaluate missing review scores.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'INVALID_REVIEW_SCORE'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'INVALID_REVIEW_SCORE',
            COUNT(*),
            SUM(
                review_score IS NOT NULL
                AND review_score NOT BETWEEN 1 AND 5
            )
        FROM olist_order_reviews_dataset;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'INVALID_REVIEW_SCORE',
            'olist_order_reviews_dataset',
            CONCAT(r.review_id, ':', r.order_id),
            'HIGH',
            'Review score is outside the permitted range.',
            CAST(r.review_score AS CHAR),
            'Non-NULL review scores must be integers from 1 through 5.'
        FROM olist_order_reviews_dataset r
        WHERE r.review_score IS NOT NULL
          AND r.review_score NOT BETWEEN 1 AND 5;

    END IF;


    -- =====================================================
    -- RULE 8: DUPLICATE REVIEW/ORDER PAIRS
    -- =====================================================
    -- PURPOSE:
    -- Identify review/order combinations that occur more than once.
    --
    -- RULE RESULT:
    -- The inner query groups review records by review_id and order_id.
    -- The outer query counts the resulting groups and sums the
    -- excess occurrences beyond the first record in each group.
    --
    -- For example, a pair occurring three times contributes two
    -- excess occurrences to failed_rows.
    --
    -- ISSUE DETAILS:
    -- GROUP BY identifies repeated pairs.
    -- HAVING COUNT(*) > 1 retains only pairs with multiple records.
    -- The occurrence count is stored as observed_value.
    --
    -- IMPORTANT:
    -- This rule checks a candidate composite key. A repeated pair
    -- should be investigated before assuming the records are invalid.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'DUPLICATE_REVIEW_PAIR'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'DUPLICATE_REVIEW_PAIR',
            COUNT(*),
            COALESCE(SUM(pair_count - 1), 0)
        FROM (
            SELECT COUNT(*) AS pair_count
            FROM olist_order_reviews_dataset
            GROUP BY review_id, order_id
        ) pairs;

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'DUPLICATE_REVIEW_PAIR',
            'olist_order_reviews_dataset',
            CONCAT(r.review_id, ':', r.order_id),
            'HIGH',
            'Review/order pair occurs more than once.',
            CONCAT('occurrences=', COUNT(*)),
            'Each review_id/order_id pair should occur once.'
        FROM olist_order_reviews_dataset r
        GROUP BY r.review_id, r.order_id
        HAVING COUNT(*) > 1;

    END IF;
    
        -- =====================================================
    -- RULE 9: DELIVERED ORDERS WITH ZERO DELIVERY DATE
    -- =====================================================
    -- PURPOSE:
    -- Identify delivered orders whose customer-delivery timestamp
    -- is represented by a zero date.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all delivered orders.
    -- failed_rows counts delivered orders matching the zero-date
    -- comparison, with COALESCE returning zero if the aggregate is NULL.
    --
    -- ISSUE DETAILS:
    -- Record each affected order ID and the observed delivery timestamp.
    -- These issues are assigned HIGH severity.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'DELIVERED_ZERO_DELIVERY_DATE'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'DELIVERED_ZERO_DELIVERY_DATE',
            COUNT(*),
            COALESCE(SUM(
                DATE_FORMAT(
                    order_delivered_customer_date,
                    '%Y-%m-%d %H:%i:%s'
                ) = '0000-00-00 00:00:00'
            ), 0)
        FROM olist_orders_dataset
        WHERE order_status = 'delivered';

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'DELIVERED_ZERO_DELIVERY_DATE',
            'olist_orders_dataset',
            o.order_id,
            'HIGH',
            'Delivered order has a zero delivery date.',
            DATE_FORMAT(
                o.order_delivered_customer_date,
                '%Y-%m-%d %H:%i:%s'
            ),
            'A delivered order should have a valid customer delivery timestamp.'
        FROM olist_orders_dataset o
        WHERE o.order_status = 'delivered'
          AND DATE_FORMAT(
              o.order_delivered_customer_date,
              '%Y-%m-%d %H:%i:%s'
          ) = '0000-00-00 00:00:00';

    END IF;


    -- =====================================================
    -- RULE 10: DELIVERED ORDERS WITH ZERO CARRIER DATE
    -- =====================================================
    -- PURPOSE:
    -- Identify delivered orders whose carrier-handoff timestamp
    -- is represented by a zero date.
    --
    -- RULE RESULT:
    -- evaluated_rows counts all delivered orders.
    -- failed_rows counts delivered orders matching the zero-date
    -- comparison.
    --
    -- ISSUE DETAILS:
    -- Store the affected order and observed carrier timestamp.
    -- These issues are assigned MEDIUM severity so that missing
    -- carrier-handoff information can be investigated.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'DELIVERED_ZERO_CARRIER_DATE'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'DELIVERED_ZERO_CARRIER_DATE',
            COUNT(*),
            COALESCE(SUM(
                DATE_FORMAT(
                    order_delivered_carrier_date,
                    '%Y-%m-%d %H:%i:%s'
                ) = '0000-00-00 00:00:00'
            ), 0)
        FROM olist_orders_dataset
        WHERE order_status = 'delivered';

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'DELIVERED_ZERO_CARRIER_DATE',
            'olist_orders_dataset',
            o.order_id,
            'MEDIUM',
            'Delivered order has a zero carrier-handoff date.',
            DATE_FORMAT(
                o.order_delivered_carrier_date,
                '%Y-%m-%d %H:%i:%s'
            ),
            'Investigate missing carrier-handoff dates for delivered orders.'
        FROM olist_orders_dataset o
        WHERE o.order_status = 'delivered'
          AND DATE_FORMAT(
              o.order_delivered_carrier_date,
              '%Y-%m-%d %H:%i:%s'
          ) = '0000-00-00 00:00:00';

    END IF;


    -- =====================================================
    -- RULE 11: DELIVERY BEFORE CARRIER HANDOFF
    -- =====================================================
    -- PURPOSE:
    -- Identify records where customer delivery is timestamped
    -- before carrier handoff.
    --
    -- DATE GUARDS:
    -- Both timestamps must be greater than '1000-01-01' so that
    -- the comparison excludes dates at or below this boundary.
    --
    -- RULE RESULT:
    -- evaluated_rows counts orders with both timestamps passing
    -- the date guards.
    -- failed_rows counts qualifying records where delivery precedes
    -- carrier handoff.
    --
    -- ISSUE DETAILS:
    -- Store both timestamps to make the chronology violation
    -- easier to investigate. These issues are assigned HIGH severity.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'DELIVERY_BEFORE_CARRIER'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'DELIVERY_BEFORE_CARRIER',
            COUNT(*),
            COALESCE(SUM(
                order_delivered_customer_date
                    < order_delivered_carrier_date
                AND order_delivered_customer_date > '1000-01-01'
                AND order_delivered_carrier_date > '1000-01-01'
            ), 0)
        FROM olist_orders_dataset
        WHERE order_delivered_customer_date > '1000-01-01'
          AND order_delivered_carrier_date > '1000-01-01';

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'DELIVERY_BEFORE_CARRIER',
            'olist_orders_dataset',
            o.order_id,
            'HIGH',
            'Customer delivery precedes carrier handoff.',
            CONCAT(
                'carrier=', o.order_delivered_carrier_date,
                '; delivery=', o.order_delivered_customer_date
            ),
            'For valid timestamps, customer delivery should not precede carrier handoff.'
        FROM olist_orders_dataset o
        WHERE o.order_delivered_customer_date
                  < o.order_delivered_carrier_date
          AND o.order_delivered_customer_date > '1000-01-01'
          AND o.order_delivered_carrier_date > '1000-01-01';

    END IF;


    -- =====================================================
    -- RULE 12: ZERO APPROVAL DATE FOR EXPECTED STATUSES
    -- =====================================================
    -- PURPOSE:
    -- Identify orders in selected progressed statuses whose
    -- approval timestamp is represented by a zero date.
    --
    -- STATUSES CHECKED:
    -- delivered, shipped, invoiced, processing, and approved.
    --
    -- RULE RESULT:
    -- evaluated_rows counts orders in the selected statuses.
    -- failed_rows counts records matching the zero-date comparison.
    --
    -- ISSUE DETAILS:
    -- Record the affected order and its status for investigation.
    -- These issues are assigned MEDIUM severity.

    IF EXISTS (
        SELECT 1
        FROM dq_rule_registry
        WHERE rule_code = 'ZERO_APPROVAL_DATE'
          AND is_active = TRUE
    ) THEN

        INSERT INTO dq_rule_results (
            run_id, rule_code, evaluated_rows, failed_rows
        )
        SELECT
            v_run_id,
            'ZERO_APPROVAL_DATE',
            COUNT(*),
            COALESCE(SUM(
                DATE_FORMAT(
                    order_approved_at,
                    '%Y-%m-%d %H:%i:%s'
                ) = '0000-00-00 00:00:00'
            ), 0)
        FROM olist_orders_dataset
        WHERE order_status IN (
            'delivered', 'shipped', 'invoiced',
            'processing', 'approved'
        );

        INSERT INTO dq_issue_details (
            run_id, rule_code, entity_table, entity_key,
            severity, issue_description, observed_value,
            expected_condition
        )
        SELECT
            v_run_id,
            'ZERO_APPROVAL_DATE',
            'olist_orders_dataset',
            o.order_id,
            'MEDIUM',
            'Order has a zero approval date despite its status.',
            CONCAT('order_status=', o.order_status),
            'Investigate zero approval dates for orders expected to have progressed beyond approval.'
        FROM olist_orders_dataset o
        WHERE o.order_status IN (
            'delivered', 'shipped', 'invoiced',
            'processing', 'approved'
        )
          AND DATE_FORMAT(
              o.order_approved_at,
              '%Y-%m-%d %H:%i:%s'
          ) = '0000-00-00 00:00:00';

    END IF;


    -- =====================================================
    -- FINALIZE RUN AND CALCULATE QUALITY SCORE
    -- =====================================================
    -- PURPOSE:
    -- Summarize the rule results generated during this run,
    -- calculate an overall quality percentage, and update run history.
    --
    -- v_rules:
    -- Number of rule-result records for the current run.
    --
    -- v_issues:
    -- Sum of failed_rows across the recorded rule results.
    --
    -- v_score:
    -- Percentage calculated as:
    -- (total evaluated rows - total failed rows)
    -- / total evaluated rows * 100.
    --
    -- If the total evaluated row count is zero, the score is NULL.
    --
    -- The run is then marked COMPLETED, the transaction is committed,
    -- and the summary record for this execution is returned.

    SELECT
        COUNT(*),
        COALESCE(SUM(failed_rows), 0),
        CASE
            WHEN SUM(evaluated_rows) = 0 THEN NULL
            ELSE ROUND(
                100.0 * (
                    SUM(evaluated_rows) - SUM(failed_rows)
                ) / SUM(evaluated_rows),
                2
            )
        END
    INTO v_rules, v_issues, v_score
    FROM dq_rule_results
    WHERE run_id = v_run_id;

    -- Update the execution history with the final metrics and status.

    UPDATE dq_validation_runs
    SET completed_at = NOW(),
        run_status = 'COMPLETED',
        total_rules_evaluated = v_rules,
        total_issues = v_issues,
        quality_score = v_score
    WHERE run_id = v_run_id;

    -- Commit the successful validation run and its recorded results.

    COMMIT;

    -- Return the summary of the completed validation run.

    SELECT
        run_id,
        run_status,
        started_at,
        completed_at,
        total_rules_evaluated,
        total_issues,
        quality_score
    FROM dq_validation_runs
    WHERE run_id = v_run_id;

END$$

-- Restore the standard SQL statement delimiter.

DELIMITER ;

-- =========================================================
-- EXECUTE THE DATA-QUALITY VALIDATION FRAMEWORK
-- =========================================================
-- PURPOSE:
-- Invoke the stored procedure to execute the active rules,
-- persist the results, and return the run summary.

CALL sp_run_data_quality_checks();