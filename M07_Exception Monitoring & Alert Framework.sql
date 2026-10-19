USE olist_analytics;

-- ============================================================
-- M07: EXCEPTION MONITORING AND ALERT FRAMEWORK
-- MySQL 8.0+
-- Purpose: Detect business exceptions, assign severity levels,
-- preserve monitoring history, and support operational follow-up.
-- ============================================================


-- SECTION 1: CREATE MONITORING RUN HISTORY
-- Purpose: Maintain one record for every execution of the alert framework.
-- Business value: Enables monitoring runs to be audited and compared over time.

CREATE TABLE IF NOT EXISTS alert_monitoring_runs (
    run_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME NULL,
    run_status VARCHAR(20) NOT NULL DEFAULT 'RUNNING',
    total_alerts INT NOT NULL DEFAULT 0
);


-- SECTION 2: CREATE ALERT DETAILS TABLE
-- Purpose: Store individual alerts generated during each monitoring run.
-- Design note: Each alert identifies a rule, severity, affected entity,
-- observed value, configured threshold, and detection timestamp.
-- The indexes support common lookups by run, rule, and severity.

CREATE TABLE IF NOT EXISTS business_alerts (
    alert_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id BIGINT NOT NULL,
    rule_code VARCHAR(50) NOT NULL,
    severity VARCHAR(10) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_key VARCHAR(150) NOT NULL,
    alert_message VARCHAR(500) NOT NULL,
    observed_value DECIMAL(18,4) NULL,
    threshold_value DECIMAL(18,4) NULL,
    detected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_alert_run (run_id),
    INDEX idx_alert_rule (rule_code),
    INDEX idx_alert_severity (severity),

    CONSTRAINT fk_business_alert_run
        FOREIGN KEY (run_id)
        REFERENCES alert_monitoring_runs(run_id)
);


-- SECTION 3: CREATE REUSABLE MONITORING PROCEDURE
-- Purpose: Centralize business exception checks in one reusable procedure.
-- Operational note: DROP PROCEDURE IF EXISTS allows the procedure
-- to be recreated when its definition is updated.

DROP PROCEDURE IF EXISTS sp_run_business_alerts;

DELIMITER $$

CREATE PROCEDURE sp_run_business_alerts()
BEGIN
    DECLARE v_run_id BIGINT;
    DECLARE v_total_alerts INT DEFAULT 0;

    -- Start a new monitoring run.
    -- Each execution receives its own run ID so that alert records
    -- can be traced to the execution that generated them.
    INSERT INTO alert_monitoring_runs (run_status)
    VALUES ('RUNNING');

    SET v_run_id = LAST_INSERT_ID();


    -- --------------------------------------------------------
    -- RULE 1: MONTHLY CANCELLATION RATE ABOVE 2%
    -- Business objective: Identify months with unusually high
    -- cancellation rates.
    -- Severity logic: Rates of 5% or more are HIGH; other
    -- qualifying rates are MEDIUM.
    -- --------------------------------------------------------

    INSERT INTO business_alerts (
        run_id, rule_code, severity, entity_type,
        entity_key, alert_message, observed_value, threshold_value
    )
    SELECT
        v_run_id,
        'HIGH_CANCELLATION_RATE',
        CASE
            WHEN 100.0 * SUM(order_status = 'canceled') / COUNT(*) >= 5
                THEN 'HIGH'
            ELSE 'MEDIUM'
        END,
        'MONTH',
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m'),
        CONCAT(
            'Monthly cancellation rate is ',
            ROUND(100.0 * SUM(order_status = 'canceled') / COUNT(*), 2),
            '%'
        ),
        ROUND(100.0 * SUM(order_status = 'canceled') / COUNT(*), 4),
        2.0
    FROM olist_orders_dataset
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_purchase_timestamp > '1000-01-01'
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
    HAVING 100.0 * SUM(order_status = 'canceled') / COUNT(*) > 2.0;


    -- --------------------------------------------------------
    -- RULE 2: MONTHLY UNAVAILABLE-ORDER RATE ABOVE 2%
    -- Business objective: Detect periods when orders are
    -- frequently marked unavailable.
    -- Severity logic: Rates of 3% or more are HIGH; other
    -- qualifying rates are MEDIUM.
    -- Business follow-up: Investigate possible inventory,
    -- listing, or fulfillment issues.
    -- --------------------------------------------------------

    INSERT INTO business_alerts (
        run_id, rule_code, severity, entity_type,
        entity_key, alert_message, observed_value, threshold_value
    )
    SELECT
        v_run_id,
        'HIGH_UNAVAILABLE_RATE',
        CASE
            WHEN 100.0 * SUM(order_status = 'unavailable') / COUNT(*) >= 3
                THEN 'HIGH'
            ELSE 'MEDIUM'
        END,
        'MONTH',
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m'),
        CONCAT(
            'Monthly unavailable-order rate is ',
            ROUND(100.0 * SUM(order_status = 'unavailable') / COUNT(*), 2),
            '%'
        ),
        ROUND(100.0 * SUM(order_status = 'unavailable') / COUNT(*), 4),
        2.0
    FROM olist_orders_dataset
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_purchase_timestamp > '1000-01-01'
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
    HAVING 100.0 * SUM(order_status = 'unavailable') / COUNT(*) > 2.0;


    -- --------------------------------------------------------
    -- RULE 3: DELIVERED MORE THAN 7 DAYS AFTER ESTIMATE
    -- Business objective: Identify delivered orders that missed
    -- their estimated delivery dates by more than seven days.
    -- Severity logic: Delays exceeding 30 days are HIGH;
    -- other qualifying delays are MEDIUM.
    -- Business follow-up: Validate extreme delays and investigate
    -- logistics performance for the affected orders.
    -- --------------------------------------------------------

    INSERT INTO business_alerts (
        run_id, rule_code, severity, entity_type,
        entity_key, alert_message, observed_value, threshold_value
    )
    SELECT
        v_run_id,
        'SEVERE_DELIVERY_DELAY',
        CASE
            WHEN delivery_vs_estimate_days > 30 THEN 'HIGH'
            ELSE 'MEDIUM'
        END,
        'ORDER',
        order_id,
        CONCAT(
            'Delivery was ',
            ROUND(delivery_vs_estimate_days, 2),
            ' days later than the estimate'
        ),
        ROUND(delivery_vs_estimate_days, 4),
        7.0
    FROM vw_order_summary
    WHERE order_status = 'delivered'
      AND delivery_vs_estimate_days > 7;


    -- --------------------------------------------------------
    -- RULE 4: DELIVERED ORDERS WITH MISSING OR INVALID PAYMENT
    -- Business objective: Identify potential payment-reconciliation
    -- exceptions among orders recorded as delivered.
    -- Severity: All records meeting this rule are marked HIGH.
    -- Business follow-up: Verify the payment transaction before
    -- classifying an exception as a genuine financial issue.
    -- --------------------------------------------------------

    INSERT INTO business_alerts (
        run_id, rule_code, severity, entity_type,
        entity_key, alert_message, observed_value, threshold_value
    )
    SELECT
        v_run_id,
        'DELIVERED_PAYMENT_EXCEPTION',
        'HIGH',
        'ORDER',
        order_id,
        CASE
            WHEN payment_record_count IS NULL
              OR payment_record_count = 0
                THEN 'Delivered order has no payment record'
            WHEN payment_amount IS NULL
                THEN 'Delivered order has a NULL payment amount'
            ELSE 'Delivered order has a zero or negative payment amount'
        END,
        payment_amount,
        0.0
    FROM vw_order_summary
    WHERE order_status = 'delivered'
      AND (
            payment_record_count IS NULL
            OR payment_record_count = 0
            OR payment_amount IS NULL
            OR payment_amount <= 0
      );


    -- --------------------------------------------------------
    -- RULE 5: HIGH-RISK ORDERS
    -- Conditions:
    -- 1. Delivery was more than 14 days late.
    -- 2. Average review score is 2 or below.
    -- 3. Merchandise value is at least R$500.
    -- All three conditions must be true.
    --
    -- Business objective: Identify cases combining poor delivery
    -- performance, customer dissatisfaction, and relatively high
    -- merchandise value for targeted investigation.
    -- --------------------------------------------------------

    INSERT INTO business_alerts (
        run_id, rule_code, severity, entity_type,
        entity_key, alert_message, observed_value, threshold_value
    )
    SELECT
        v_run_id,
        'HIGH_RISK_CUSTOMER_EXPERIENCE',
        'HIGH',
        'ORDER',
        order_id,
        CONCAT(
            'Late by ',
            ROUND(delivery_vs_estimate_days, 2),
            ' days; review score ',
            ROUND(average_review_score, 2),
            '; merchandise value R$',
            ROUND(merchandise_amount, 2)
        ),
        merchandise_amount,
        500.0
    FROM vw_order_summary
    WHERE order_status = 'delivered'
      AND delivery_vs_estimate_days > 14
      AND average_review_score IS NOT NULL
      AND average_review_score <= 2
      AND merchandise_amount >= 500;


    -- Finalize the monitoring run.
    -- Count only alerts associated with the current run ID.
    -- This keeps the run-level total separate from historical alerts.
    SELECT COUNT(*)
    INTO v_total_alerts
    FROM business_alerts
    WHERE run_id = v_run_id;

    -- Mark the run as completed and save its final alert count.
    UPDATE alert_monitoring_runs
    SET completed_at = CURRENT_TIMESTAMP,
        run_status = 'COMPLETED',
        total_alerts = v_total_alerts
    WHERE run_id = v_run_id;

END$$

DELIMITER ;


-- ============================================================
-- SECTION 4: RUN THE MONITORING FRAMEWORK
-- Each CALL creates a new run and preserves previous results.
-- ============================================================

-- Execute all five business exception rules.
CALL sp_run_business_alerts();


-- ============================================================
-- SECTION 5: VALIDATE THE LATEST RUN
-- Purpose: Verify execution history and inspect generated alerts.
-- ============================================================

-- Review recent runs to confirm completion status and alert totals.
SELECT *
FROM alert_monitoring_runs
ORDER BY run_id DESC
LIMIT 5;


-- Retrieve all alerts associated with the latest monitoring run.
-- Severity ordering places HIGH alerts before MEDIUM alerts.
SELECT a.*
FROM business_alerts a
WHERE a.run_id = (
    SELECT MAX(run_id)
    FROM alert_monitoring_runs
)
ORDER BY
    CASE a.severity
        WHEN 'HIGH' THEN 1
        WHEN 'MEDIUM' THEN 2
        ELSE 3
    END,
    a.rule_code,
    a.entity_key;


-- Summarize the latest run by rule and severity.
-- Purpose: Identify which rules contribute the most alerts
-- and how those alerts are distributed by severity.
SELECT
    rule_code,
    severity,
    COUNT(*) AS alert_count
FROM business_alerts
WHERE run_id = (
    SELECT MAX(run_id)
    FROM alert_monitoring_runs
)
GROUP BY rule_code, severity
ORDER BY rule_code, severity;


-- ============================================================
-- SECTION 6: MONITORING SUMMARY
-- Purpose: Produce a compact summary of alert volumes by rule.
-- ============================================================

-- Compare total alerts and severity counts across the rules
-- generated during the latest monitoring run.
SELECT
    rule_code,
    COUNT(*) AS total_alerts,
    SUM(severity = 'HIGH') AS high_severity_alerts,
    SUM(severity = 'MEDIUM') AS medium_severity_alerts
FROM business_alerts
WHERE run_id = (
    SELECT MAX(run_id)
    FROM alert_monitoring_runs
)
GROUP BY rule_code
ORDER BY total_alerts DESC;


-- Reconfirm the active database before producing the final
-- rule-by-severity summary.
USE olist_analytics;

-- Final monitoring summary by exception rule and severity.
-- Useful for reporting alert distribution and prioritizing follow-up.
SELECT
    rule_code,
    severity,
    COUNT(*) AS alert_count
FROM business_alerts
WHERE run_id = (
    SELECT MAX(run_id)
    FROM alert_monitoring_runs
)
GROUP BY rule_code, severity
ORDER BY rule_code, severity;

-- ============================================================
-- KEY BUSINESS INSIGHTS
-- ============================================================

-- 1. Delivery delays are the biggest operational concern.
-- A total of 2,862 orders were delivered more than seven days
-- after their estimated delivery dates, including 345 orders
-- with delays exceeding 30 days.
-- Business implication: Delivery performance requires focused
-- attention, particularly for severely delayed orders. Reviewing
-- logistics performance and delivery timelines can help identify
-- opportunities to improve customer satisfaction.


-- 2. Forty-nine orders fall into the high-risk customer experience
-- category.
-- These orders were delivered more than 14 days late, received
-- review scores of 2 or below, and had merchandise values of
-- at least R$500.
-- Business implication: These cases combine poor delivery
-- performance, negative customer feedback, and relatively high
-- merchandise value, making them priorities for service recovery.


-- 3. Four months exceeded the cancellation-rate threshold.
-- The monitoring framework flags months with cancellation rates
-- above 2%.
-- Business implication: Reviewing cancellation patterns and
-- underlying reasons can help identify recurring operational
-- issues and opportunities to reduce order cancellations.


-- 4. Two months exceeded the unavailable-order threshold.
-- These months recorded unavailable-order rates above 2%.
-- Business implication: Inventory availability, product listings,
-- and seller fulfillment practices are potential areas for
-- investigation to reduce unsuccessful orders.


-- 5. One delivered order has a payment-record exception.
-- The order has no associated payment record in the analytical
-- summary, despite being marked as delivered.
-- Business implication: This exception highlights the importance
-- of payment reconciliation and accurate order-level financial
-- records.