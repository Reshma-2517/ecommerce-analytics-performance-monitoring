USE olist_analytics;

-- ============================================================
-- M08: SNAPSHOT MANAGEMENT AND AUDITABILITY
-- Purpose: Preserve KPI values over time and track changes
-- between successive snapshots.
-- ============================================================


-- SECTION 1: Add a unique identifier to the existing snapshot
-- table. Run this section only once.
-- Design rationale: A unique snapshot ID identifies each
-- historical record and supports chronological comparisons.

ALTER TABLE kpi_summary_snapshot
ADD COLUMN snapshot_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST;


-- SECTION 2: Create a snapshot capture procedure
-- Purpose: Capture the current KPI metrics and payment total
-- as a single historical snapshot.
-- Design rationale: The procedure centralizes snapshot logic
-- so each execution follows the same calculation process.

DROP PROCEDURE IF EXISTS sp_capture_kpi_snapshot;

DELIMITER $$

CREATE PROCEDURE sp_capture_kpi_snapshot()
BEGIN
    -- Insert the current KPI values into the snapshot history.
    -- Each execution creates a new record rather than replacing
    -- previously captured values.
    INSERT INTO kpi_summary_snapshot (
        total_orders,
        delivered_orders,
        canceled_orders,
        cancellation_rate,
        merchandise_value,
        freight_value,
        average_order_value,
        average_delivery_days,
        on_time_delivery_rate,
        average_review_score,
        total_payment_value,
        calculated_at
    )
    SELECT
        m.total_orders,
        m.delivered_orders,
        m.canceled_orders,
        m.cancellation_rate,
        m.merchandise_value,
        m.freight_value,
        m.average_order_value,
        m.average_delivery_days,
        m.on_time_delivery_rate,
        m.average_review_score,
        COALESCE(p.total_payment_value, 0),
        CURRENT_TIMESTAMP
    FROM vw_kpi_order_metrics AS m
    CROSS JOIN (
        -- Aggregate payment values separately to produce one
        -- total for the snapshot.
        SELECT COALESCE(SUM(payment_amount), 0)
               AS total_payment_value
        FROM vw_order_payment_summary
    ) AS p;
END$$

DELIMITER ;


-- SECTION 3: Capture a new snapshot
-- Every call adds a new historical record.
-- Business value: Repeated snapshots make it possible to compare
-- KPI values across different capture times.

CALL sp_capture_kpi_snapshot();


-- SECTION 4: Inspect snapshot history
-- Review stored KPI records, with the most recent snapshot first.
-- This provides a chronological audit trail of captured metrics.

SELECT *
FROM kpi_summary_snapshot
ORDER BY snapshot_id DESC;


-- SECTION 5: Compare the latest two snapshots
-- Purpose: Calculate changes in key business KPIs between
-- consecutive snapshots.
-- Analytical approach: LAG retrieves the previous snapshot's
-- values without requiring a self-join.

WITH snapshot_comparison AS (
    SELECT
        snapshot_id,
        calculated_at,
        total_orders,
        delivered_orders,
        canceled_orders,
        cancellation_rate,
        merchandise_value,
        freight_value,
        average_order_value,
        average_delivery_days,
        on_time_delivery_rate,
        average_review_score,
        total_payment_value,

        -- Retrieve the identifier and KPI values from the
        -- preceding snapshot for comparison.
        LAG(snapshot_id) OVER (
            ORDER BY snapshot_id
        ) AS previous_snapshot_id,

        LAG(total_orders) OVER (
            ORDER BY snapshot_id
        ) AS previous_total_orders,

        LAG(merchandise_value) OVER (
            ORDER BY snapshot_id
        ) AS previous_merchandise_value,

        LAG(cancellation_rate) OVER (
            ORDER BY snapshot_id
        ) AS previous_cancellation_rate,

        LAG(on_time_delivery_rate) OVER (
            ORDER BY snapshot_id
        ) AS previous_on_time_delivery_rate,

        LAG(average_review_score) OVER (
            ORDER BY snapshot_id
        ) AS previous_average_review_score

    FROM kpi_summary_snapshot
)
SELECT
    snapshot_id,
    previous_snapshot_id,
    calculated_at,

    -- Order-volume movement between the two snapshots.
    total_orders,
    total_orders - previous_total_orders
        AS change_in_orders,

    -- Change in merchandise value, useful for tracking
    -- movement in the overall merchandise sales measure.
    merchandise_value,
    merchandise_value - previous_merchandise_value
        AS change_in_merchandise_value,

    -- A positive cancellation-rate change indicates an increase
    -- in the recorded cancellation rate.
    cancellation_rate,
    cancellation_rate - previous_cancellation_rate
        AS change_in_cancellation_rate,

    -- A positive change indicates an improvement in the
    -- recorded on-time delivery rate.
    on_time_delivery_rate,
    on_time_delivery_rate - previous_on_time_delivery_rate
        AS change_in_on_time_delivery_rate,

    -- Track movement in the average customer review score.
    average_review_score,
    average_review_score - previous_average_review_score
        AS change_in_average_review_score

FROM snapshot_comparison
WHERE previous_snapshot_id IS NOT NULL
ORDER BY snapshot_id DESC
LIMIT 1;


-- SECTION 6: Verify snapshot count and latest timestamp
-- Purpose: Summarize the available snapshot history.
-- total_snapshots indicates the number of captured records,
-- while the timestamps show the history's time range.

SELECT
    COUNT(*) AS total_snapshots,
    MAX(calculated_at) AS latest_snapshot_at,
    MIN(calculated_at) AS earliest_snapshot_at
FROM kpi_summary_snapshot;