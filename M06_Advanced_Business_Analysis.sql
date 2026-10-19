-- ============================================================
-- M06: ADVANCED BUSINESS ANALYSIS
-- SECTION 1: SALES AND ORDER TRENDS
-- PURPOSE: Analyze order growth, merchandise value, and
--          average merchandise value per order over time.
-- ============================================================

-- Select the analytics database.
USE olist_analytics;


-- Q1. How do monthly order volumes change over time?
-- GRAIN: One row per purchase month.
-- PURPOSE: Identify demand trends and potential peak periods.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS total_orders
FROM vw_order_summary
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp > '1000-01-01'
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- Insight: Order volume increased considerably throughout 2017. November 2017 recorded 7,544 orders in the visible results,
-- while monthly volumes remained relatively high during 2018.

-- Business implication: Sustained order growth indicates greater demand on sellers, inventory, logistics, and customer support.
-- The business should ensure its operational capacity can handle peak demand without compromising delivery performance.

-- Recommendation: Investigate peak months to identify demand patterns and plan inventory and logistics capacity accordingly.


-- Q2. How does monthly merchandise value change over time?
-- GRAIN: One row per purchase month.
-- PURPOSE: Track merchandise value independently of payment totals.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    ROUND(SUM(merchandise_amount), 2) AS merchandise_value_brl
FROM vw_order_summary
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp > '1000-01-01'
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- Insight: Merchandise value increased from approximately R$120,312 in January 2017 to over R$1 million in November 2017.
-- March 2018 reached approximately R$983,213. The early and late 2016/2018 values are much smaller, likely because those months have incomplete dataset coverage.

-- Business implication: The increase suggests substantial growth in merchandise sales value during 2017.
-- However, monthly value depends on both order volume and the value of items per order.

-- Recommendation: Compare monthly merchandise value with order volume and average order value to understand what drives the growth.


-- Q3. Which months have the highest and lowest order volumes?
-- PURPOSE: Identify peak and minimum observed months.
-- The query returns every month tied for the maximum or minimum.

WITH monthly_orders AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
        COUNT(*) AS total_orders
    FROM vw_order_summary
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_purchase_timestamp > '1000-01-01'
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
)
SELECT
    order_month,
    total_orders,
    CASE
        WHEN total_orders = (SELECT MAX(total_orders) FROM monthly_orders)
            THEN 'Highest order volume'
        WHEN total_orders = (SELECT MIN(total_orders) FROM monthly_orders)
            THEN 'Lowest order volume'
        ELSE 'Other'
    END AS volume_classification
FROM monthly_orders
WHERE total_orders = (SELECT MAX(total_orders) FROM monthly_orders)
   OR total_orders = (SELECT MIN(total_orders) FROM monthly_orders)
ORDER BY total_orders DESC;

-- Insight: November 2017 had the highest order volume, with 7,544 orders. December 2016 had the lowest, with just 1 order.

-- Business implication: November 2017 may represent a peak-demand period.
-- December 2016 is too small to make a meaningful comparison with established operating months and may reflect the dataset's limited early coverage.

-- Recommendation: Investigate November 2017 for potential promotional or seasonal demand. Avoid treating December 2016 as a normal baseline.


-- Q4. How do delivered, canceled, and unavailable orders vary by month?
-- PURPOSE: Compare monthly order-status counts.
-- NOTE: These are counts, not status percentages.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'delivered'
             THEN 1 ELSE 0 END) AS delivered_orders,
    SUM(CASE WHEN order_status = 'canceled'
             THEN 1 ELSE 0 END) AS canceled_orders,
    SUM(CASE WHEN order_status = 'unavailable'
             THEN 1 ELSE 0 END) AS unavailable_orders
FROM vw_order_summary
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp > '1000-01-01'
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- Insight: November 2017 recorded 7,544 orders, including 7,289 delivered, 37 canceled, and 84 unavailable.
-- In August 2018, 6,512 orders included 6,351 delivered, 84 canceled, and 7 unavailable. September and October 2018 show very low order counts in the displayed results.

-- Business implication: Delivered orders make up most orders in the higher-volume months, but cancellation and unavailable-order patterns vary.
-- The sharp drop in late 2018 may indicate incomplete data coverage rather than a real business decline.

-- Recommendation: Compare cancellation and unavailable rates across complete months before identifying operational problems.
-- Investigate months with unusually high rates rather than relying only on raw counts.


-- Q5. Is merchandise value growing or declining month over month?
-- PURPOSE: Compare each month's merchandise value with the preceding observed month.
-- LAG() retrieves the previous row's value based on chronological order.

WITH monthly_value AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
        SUM(merchandise_amount) AS merchandise_value
    FROM vw_order_summary
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_purchase_timestamp > '1000-01-01'
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
),
monthly_comparison AS (
    SELECT
        order_month,
        merchandise_value,
        LAG(merchandise_value) OVER (
            ORDER BY order_month
        ) AS previous_month_value
    FROM monthly_value
)
SELECT
    order_month,
    ROUND(merchandise_value, 2) AS merchandise_value_brl,
    ROUND(previous_month_value, 2) AS previous_month_value_brl,
    ROUND(
        merchandise_value - previous_month_value, 2
    ) AS change_brl,
    ROUND(
        100.0 * (merchandise_value - previous_month_value)
        / NULLIF(previous_month_value, 0),
        2
    ) AS change_percentage,
    CASE
        WHEN previous_month_value IS NULL THEN 'No previous month'
        WHEN merchandise_value > previous_month_value THEN 'Growing'
        WHEN merchandise_value < previous_month_value THEN 'Declining'
        ELSE 'Unchanged'
    END AS trend
FROM monthly_comparison
ORDER BY order_month;

-- Insight: Merchandise value fluctuates rather than increasing consistently.
-- The largest visible increase occurred in November 2017, when value rose by approximately R$346,052 (52.10%) from October.
-- The largest visible decline occurred in June 2018, when value fell by approximately R$131,393 (13.19%) from May. Growth resumed in July 2018, reaching 3.51%.

-- Business implication: These fluctuations suggest that merchandise sales value is sensitive to changes in order demand and/or average order value.
-- The November 2017 increase may reflect a peak-demand period, while the June 2018 decline warrants investigation. The data alone does not establish the causes.

-- Recommendation: Compare monthly order volume and average order value to determine whether changes are driven by the number of orders or the value of each order.
-- Also, treat the final months cautiously because incomplete data can distort month-over-month comparisons.


-- Q6. How does average merchandise value per order vary by month?
-- DENOMINATOR: Orders with at least one item record.
-- PURPOSE: Distinguish order-volume growth from changes in average order value.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS orders_with_items,
    ROUND(SUM(merchandise_amount), 2) AS merchandise_value_brl,
    ROUND(
        SUM(merchandise_amount) / NULLIF(COUNT(*), 0),
        2
    ) AS average_merchandise_value_per_order_brl
FROM vw_order_summary
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp > '1000-01-01'
  AND order_item_count > 0
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- Insight: Average merchandise value per order fluctuated between approximately R$125 and R$160 during most of 2017–2018.
-- It peaked at R$160.74 in October 2016 among the visible months, while November 2017 averaged R$135.59 despite having the highest order volume.
-- This suggests that higher order volume does not necessarily mean higher spending per order.

-- Business implication: Merchandise value growth may be driven more by increasing order volume than by customers spending more per order.
-- The business should distinguish between acquiring more orders and increasing average order value when evaluating performance.

-- Recommendation: Investigate categories and product combinations that contribute to higher-value orders.
-- Consider product bundles or cross-selling strategies, and evaluate their impact on average order value without assuming that higher spending automatically means higher profit.


-- ============================================================
-- SECTION 2: DELIVERY & LOGISTICS PERFORMANCE
-- PURPOSE: Evaluate delivery reliability, regional differences,
--          category-level delivery times, and customer feedback.
-- ============================================================

-- Select the analytics database.
USE olist_analytics;


-- Q7. What percentage of eligible delivered orders arrive on time?
-- ELIGIBILITY: Delivered orders with valid delivery and estimate dates.
-- A delivery is on time when actual delivery is on or before the estimate.

SELECT
    COUNT(*) AS eligible_delivered_orders,
    SUM(CASE
        WHEN delivery_vs_estimate_days <= 0 THEN 1
        ELSE 0
    END) AS on_time_orders,
    SUM(CASE
        WHEN delivery_vs_estimate_days > 0 THEN 1
        ELSE 0
    END) AS late_orders,
    ROUND(
        100.0 * SUM(CASE
            WHEN delivery_vs_estimate_days <= 0 THEN 1
            ELSE 0
        END) / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_delivery_rate_pct
FROM vw_order_summary
WHERE order_status = 'delivered'
  AND delivery_vs_estimate_days IS NOT NULL;

-- Insight: Out of 96,470 eligible delivered orders, 89,936 arrived on time or early, while 6,534 were late.
-- The on-time delivery rate is 93.23%, meaning approximately 6.77% of eligible orders missed their estimated delivery dates.

-- Business implication: Delivery performance is strong overall, but thousands of late deliveries can still damage customer satisfaction and increase complaints.

-- Recommendation: Investigate the causes of late deliveries and monitor the on-time delivery rate monthly, with a target of improving performance beyond 95%.


-- Q8. Which customer states have the longest average delivery times?
-- GRAIN: One row per customer state.
-- Only delivered orders with valid delivery durations are included.
-- States with fewer than 100 eligible orders are excluded to reduce
-- the influence of very small samples.

SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM vw_order_summary
WHERE order_status = 'delivered'
  AND delivery_days IS NOT NULL
  AND customer_state IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY avg_delivery_days DESC
LIMIT 10;

-- Insight: Amazonas (AM) has the highest average delivery time at 26.40 days, followed by Alagoas (AL) at 24.52 days and Pará (PA) at 23.75 days.
-- In comparison, Bahia (BA) averages 19.31 days among the states shown.

-- Business implication: Delivery duration varies considerably by customer location.
-- Longer transit times may reflect geographic distance, logistics coverage, carrier performance, or regional infrastructure constraints.
-- The results alone do not establish which factor is responsible.

-- Recommendation: Review carrier performance, shipping routes, and delivery estimates in the slowest states.
-- Consider regional logistics partners or distribution improvements where order volumes justify them.


-- Q9. Which product categories have the longest delivery times?
-- GRAIN: One row per product category.
-- Each order is counted once per category it contains.
-- Only delivered orders with valid delivery durations are included.

SELECT
    d.product_category_name,
    COUNT(DISTINCT d.order_id) AS delivered_orders,
    ROUND(AVG(o.delivery_days), 2) AS avg_delivery_days
FROM vw_order_item_detail AS d
JOIN vw_order_summary AS o
    ON d.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.delivery_days IS NOT NULL
  AND d.product_category_name IS NOT NULL
GROUP BY d.product_category_name
HAVING COUNT(DISTINCT d.order_id) >= 100
ORDER BY avg_delivery_days DESC
LIMIT 10;

-- Insight: The moveis_escritorio (office furniture) category has the longest average delivery time among the categories shown, at 20.82 days across 1,254 delivered orders.
-- Christmas articles average 15.72 days, while fashion footwear averages 15.42 days. By comparison, garden tools average 13.69 days across 3,448 orders.

-- Business implication: Some categories may create greater delivery challenges because of product dimensions, handling requirements, seller locations, or shipping routes.
-- These are potential explanations, not confirmed causes.

-- Recommendation: Analyze seller locations, freight charges, and carrier performance for the slowest categories.
-- Use category-specific delivery estimates where the data supports them.


-- Q10. How strongly are delivery delays associated with low review scores?
-- PURPOSE: Compare average review score and low-review rate by delivery group.
-- This is an association analysis, not proof of causation.

SELECT
    CASE
        WHEN o.delivery_vs_estimate_days <= 0 THEN 'On time or early'
        WHEN o.delivery_vs_estimate_days > 0 THEN 'Late'
    END AS delivery_group,
    COUNT(*) AS reviewed_delivered_orders,
    ROUND(AVG(o.average_review_score), 2) AS avg_review_score,
    ROUND(
        100.0 * SUM(CASE
            WHEN o.average_review_score <= 2 THEN 1
            ELSE 0
        END) / NULLIF(COUNT(*), 0),
        2
    ) AS low_review_rate_pct
FROM vw_order_summary AS o
WHERE o.order_status = 'delivered'
  AND o.delivery_vs_estimate_days IS NOT NULL
  AND o.average_review_score IS NOT NULL
GROUP BY
    CASE
        WHEN o.delivery_vs_estimate_days <= 0 THEN 'On time or early'
        WHEN o.delivery_vs_estimate_days > 0 THEN 'Late'
    END
ORDER BY delivery_group;

-- Insight: Late deliveries have an average review score of just 2.27 out of 5, compared with 4.29 for orders delivered on time or early.
-- Additionally, 62.36% of reviewed late orders received scores of 2 or below, compared with only 9.23% of on-time or early orders.

-- Business implication: Delivery delays are strongly associated with poorer customer feedback.
-- This suggests that logistics performance is an important contributor to customer experience, although other factors may also affect reviews.

-- Recommendation: Prioritize late-order prevention and proactive customer communication.
-- Track review scores alongside delivery performance to assess whether logistics improvements correspond with better customer satisfaction.


-- Q11. Which delivered orders have the most severe delivery delays?
-- PURPOSE: Identify extreme exceptions for individual investigation.
-- days_late measures the difference between actual and estimated
-- delivery dates; positive values indicate late delivery.

SELECT
    order_id,
    customer_state,
    order_purchase_timestamp,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    delivery_days,
    delivery_vs_estimate_days AS days_late,
    average_review_score
FROM vw_order_summary
WHERE order_status = 'delivered'
  AND delivery_vs_estimate_days > 0
ORDER BY delivery_vs_estimate_days DESC
LIMIT 20;

-- Insight: The most delayed order in the results was approximately 188 days late, with a delivery duration of about 208 days.
-- Several other orders were more than 150 days late. The displayed orders also include very low review scores, including scores of 1 and 2, as well as a missing review score.

-- Business implication: Delays of this magnitude are extreme exceptions, not ordinary delivery variation.
-- They may indicate serious fulfillment failures, unusual order histories, or data-quality issues that require individual investigation.

-- Recommendation: Investigate these orders individually, checking purchase dates, estimated delivery dates, carrier handoff dates,
-- and delivery timestamps. Verify whether the records reflect genuine delivery failures before drawing operational conclusions.


-- Q12. Which customer states generate the highest number of orders?
-- GRAIN: One row per customer state.
-- PURPOSE: Identify geographic concentrations of order activity.

SELECT
    customer_state,
    COUNT(*) AS total_orders,
    COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM vw_order_summary
GROUP BY customer_state
ORDER BY total_orders DESC
LIMIT 10;

-- Insight: São Paulo (SP) dominates with 41,746 orders from 40,302 unique customers, followed by Rio de Janeiro (RJ) with 12,852 orders
-- and Minas Gerais (MG) with 11,635. SP generates substantially more orders than any other state in the top 10.

-- Business implication: São Paulo is the company's strongest market in terms of order volume.
-- Its large customer base makes it an important region for customer acquisition, retention, and logistics planning.

-- Recommendation: Prioritize customer retention and targeted marketing in SP.
-- Evaluate other states with lower order volumes to identify opportunities for expansion.


-- Q13. How many customers make repeat purchases?
-- GRAIN: One row per customer_unique_id.
-- PURPOSE: Measure observed repeat purchasing at the customer level.

WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM vw_order_summary
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN order_count = 1 THEN 1 ELSE 0 END)
        AS one_time_customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END)
        AS repeat_customers,
    ROUND(
        100.0 * SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_rate_pct
FROM customer_orders;

-- Insight: Out of 96,096 unique customers, 93,099 (96.88%) made only one purchase, while just 2,997 (3.12%) made repeat purchases.

-- Business implication: The business relies heavily on one-time buyers and has a low observed repeat-customer rate.
-- This may indicate an opportunity to improve customer loyalty, although the dataset's observation period and the nature of customers' purchases should also be considered.

-- Recommendation: Test post-purchase email campaigns, personalized product recommendations, and loyalty incentives.
-- Measure whether these initiatives increase repeat purchases over time.


-- Q14. Which customer states have the highest average review scores?
-- GRAIN: One row per customer state.
-- States with fewer than 100 reviewed orders are excluded.

SELECT
    customer_state,
    COUNT(*) AS reviewed_orders,
    ROUND(AVG(average_review_score), 2) AS avg_review_score
FROM vw_order_summary
WHERE average_review_score IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY avg_review_score DESC
LIMIT 10;

-- Insight: Amazonas (AM) leads with an average review score of 4.21/5 across 146 reviewed orders,
-- followed by Paraná (PR) at 4.18 across 5,019 reviews and São Paulo (SP) at 4.17 across 41,472 reviews.
-- The scores are relatively close, but the number of reviews differs substantially.

-- Business implication: Customer satisfaction appears strong across the highest-rated states.
-- However, AM's smaller sample means its score is less representative of overall customer experience than SP's score.

-- Recommendation: Use both average scores and review volumes when comparing regions.
-- Investigate the practices and delivery performance of consistently high-rated regions to identify improvements that could be applied elsewhere.


-- Q15. How does customer satisfaction vary by order status?
-- GRAIN: One row per order status.
-- Review averages exclude NULL scores, while total_orders includes
-- all orders in each status.

SELECT
    order_status,
    COUNT(*) AS total_orders,
    COUNT(average_review_score) AS reviewed_orders,
    ROUND(AVG(average_review_score), 2) AS avg_review_score
FROM vw_order_summary
GROUP BY order_status
ORDER BY avg_review_score ASC;

-- Insight: Delivered orders have an average review score of 4.16/5, whereas processing orders average 1.27, unavailable orders 1.53, canceled orders 1.80, and shipped orders 2.00.
-- These results show a substantial difference in satisfaction across order statuses.

-- Business implication: Customers may be more dissatisfied when orders are delayed, canceled, unavailable, or still unresolved.
-- However, the results do not prove that order status alone causes lower ratings; the smaller review samples and timing of reviews also matter.

-- Recommendation: Investigate low-rated processing, unavailable, and canceled orders to identify recurring issues.
-- Improve customer communication and resolution processes, and monitor review scores alongside fulfillment status.


-- Q16. Which customers have the highest total merchandise spending?
-- GRAIN: One row per customer_unique_id.
-- PURPOSE: Identify high-value customers based on accumulated
-- merchandise value, rather than payment value or profit.

SELECT
    customer_unique_id,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(merchandise_amount), 2) AS total_merchandise_spend
FROM vw_order_summary
GROUP BY customer_unique_id
HAVING SUM(merchandise_amount) > 0
ORDER BY total_merchandise_spend DESC
LIMIT 10;

-- Insight: The highest-spending customer in the results has merchandise spending of R$13,440 across one order.
-- The second customer spent R$7,388 across two orders, while the third spent R$7,160 across one order.
-- Most of the displayed top spenders have only one recorded order.

-- Business implication: High spending does not necessarily indicate customer loyalty.
-- A customer may spend substantially in a single transaction without returning,
-- so the business should distinguish high-value purchases from sustained customer relationships.

-- Recommendation: Analyze high-spending customers by order frequency, average order value, and recency.
-- Consider targeted retention campaigns for customers with high spending but no subsequent purchases.

-- Q17. Which payment methods contribute the most to total payment value?
-- Purpose: Compare payment methods by payment-record volume, distinct orders, and total value.
-- Analytical note: An order may have multiple payment records, so payment_records and distinct_orders
-- measure different things.

SELECT
    payment_type,
    COUNT(*) AS payment_records,
    COUNT(DISTINCT order_id) AS distinct_orders,
    ROUND(SUM(payment_value), 2) AS total_payment_value,
    ROUND(AVG(payment_value), 2) AS average_payment_value
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- Insight: Credit cards dominate, contributing approximately R$12.54 million across 76,505 distinct orders.
-- Boleto contributes R$2.87 million, followed by vouchers at R$379,436.87 and debit cards at R$217,989.79.

-- Business implication: Credit cards are the primary payment channel, so payment reliability
-- and checkout performance for this method are particularly important.
-- Boleto also represents a substantial payment channel and should not be overlooked.

-- Recommendation: Prioritize credit-card checkout reliability while monitoring payment success
-- and customer behavior across other methods.


-- Q18. How does the average payment value vary by payment method and installment count?
-- Purpose: Compare payment values across payment methods and installment plans.
-- Analytical note: Total payment value reflects both payment size and the number of records;
-- average payment value provides a complementary measure.

SELECT
    payment_type,
    payment_installments,
    COUNT(*) AS payment_records,
    ROUND(AVG(payment_value), 2) AS avg_payment_value,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM olist_order_payments_dataset
GROUP BY payment_type, payment_installments
ORDER BY total_payment_value DESC
LIMIT 15;

-- Insight: Credit-card payments with one installment have the highest total payment value, at approximately R$2.44 million.
-- Ten-installment payments contribute another R$2.21 million. Average payment values generally increase for longer installment plans,
-- although the number of records decreases substantially at higher installment counts.

-- Business implication: Installment payments may help customers make larger purchases,
-- but the results show payment values rather than proof that installments cause higher spending.

-- Recommendation: Compare installment patterns with order value and product category to understand where installment
-- options are most relevant. Avoid drawing conclusions from small groups, such as the 74 records with 15 installments.


-- Q19. Which product categories generate the highest merchandise value and freight costs?
-- Purpose: Identify high-value categories and compare their merchandise value with freight costs.
-- Analytical note: The freight-to-merchandise percentage provides context for logistics costs relative to sales value.

SELECT
    product_category_name,
    COUNT(DISTINCT order_id) AS distinct_orders,
    ROUND(SUM(item_price), 2) AS merchandise_value,
    ROUND(SUM(item_freight_value), 2) AS freight_cost,
    ROUND(
        100.0 * SUM(item_freight_value)
        / NULLIF(SUM(item_price), 0),
        2
    ) AS freight_to_merchandise_pct
FROM vw_order_item_detail
GROUP BY product_category_name
HAVING SUM(item_price) > 0
ORDER BY merchandise_value DESC
LIMIT 10;

-- Insight: beleza_saude (health and beauty) leads the displayed categories with R$1.26 million in merchandise value across 8,836 orders and R$182,566.73 in freight costs.
-- relogios_presentes (watches and gifts) follows with R$1.21 million. The cama_mesa_banho category has a particularly high freight-to-merchandise ratio of 19.74%.

-- Business implication: High-volume categories contribute substantially to merchandise sales, but freight costs vary by category.
-- Strong sales alone do not reveal which categories are most profitable.

-- Recommendation: Track freight costs alongside merchandise value by category. Prioritize high-value categories for logistics optimization,
-- especially where freight consumes a large share of merchandise value.


-- Q20. Which product categories have the highest freight cost relative to merchandise value?
-- Purpose: Highlight categories where freight represents a large proportion of merchandise value.
-- Analytical note: The minimum merchandise-value threshold helps avoid prioritizing categories with very small sales totals.

SELECT
    product_category_name,
    COUNT(*) AS order_item_count,
    ROUND(SUM(item_price), 2) AS merchandise_value,
    ROUND(SUM(item_freight_value), 2) AS freight_cost,
    ROUND(
        100.0 * SUM(item_freight_value)
        / NULLIF(SUM(item_price), 0),
        2
    ) AS freight_to_merchandise_pct
FROM vw_order_item_detail
GROUP BY product_category_name
HAVING SUM(item_price) >= 10000
ORDER BY freight_to_merchandise_pct DESC
LIMIT 10;

-- Insight: sinalizacao_e_seguranca (signaling and security) has the highest freight-to-merchandise ratio at 30.26%, followed by alimentos_bebidas (food and beverages)
-- at 29.70% and eletronicos (electronics) at 29.07%. Furniture categories also show high ratios, including moveis_sala at 26.07%.

-- Business implication: Freight represents a substantial share of merchandise value in these categories.
-- This could put pressure on margins or make purchases less attractive to customers, although actual profitability cannot be determined without additional cost data.

-- Recommendation: Examine shipping charges, product dimensions, seller locations, and carrier rates for the highest-ratio categories.
-- Consider negotiated shipping rates or category-specific delivery strategies where feasible.


-- Q21. How does monthly merchandise value compare with total payment value?
-- Purpose: Compare merchandise value and payment value by purchase month.
-- Analytical note: Monthly payment totals are aggregated separately before joining to the order summary.
-- This avoids directly joining order-level payment totals to item-level rows and multiplying merchandise amounts.

SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    ROUND(SUM(o.merchandise_amount), 2) AS merchandise_value,
    ROUND(COALESCE(p.monthly_payment_value, 0), 2)
        AS payment_value,
    ROUND(
        COALESCE(p.monthly_payment_value, 0)
        - SUM(o.merchandise_amount),
        2
    ) AS payment_minus_merchandise
FROM vw_order_summary o
LEFT JOIN (
    SELECT
        DATE_FORMAT(ord.order_purchase_timestamp, '%Y-%m') AS order_month,
        SUM(pay.payment_amount) AS monthly_payment_value
    FROM vw_order_summary ord
    JOIN vw_order_payment_summary pay
        ON ord.order_id = pay.order_id
    GROUP BY DATE_FORMAT(ord.order_purchase_timestamp, '%Y-%m')
) p
    ON DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') = p.order_month
WHERE o.order_purchase_timestamp IS NOT NULL
  AND o.order_purchase_timestamp > '1000-01-01'
GROUP BY
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'),
    p.monthly_payment_value
ORDER BY order_month;

-- Insight: The displayed results show that monthly payment value exceeds merchandise value in most months.
-- For example, in November 2017, merchandise value was approximately R$1.01 million, while payment value was R$1.19 million—a difference of around R$184,611. In October 2016, payment value exceeded merchandise value by R$9,582.82.

-- Business implication: Payment totals and merchandise totals measure different things.
-- Payment records can reflect freight, installments, vouchers, and other payment characteristics, so the difference should not automatically be treated as profit or a discrepancy.

-- Recommendation: Compare merchandise value, freight value, and payment value separately. Investigate unusual differences at the order level before using these measures for financial reporting.


-- =======================================================================================================
-- Seller & Product Performance Analysis
-- =======================================================================================================

-- Q22. Which sellers generate the highest merchandise value?
-- Purpose: Rank sellers by merchandise value while comparing order volume and item count.
-- Analytical note: Distinct orders measure order reach; order_items measures the number of item rows.

SELECT
    seller_id,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(*) AS order_items,
    ROUND(SUM(item_price), 2) AS merchandise_value,
    ROUND(SUM(item_freight_value), 2) AS freight_value
FROM vw_order_item_detail
GROUP BY seller_id
ORDER BY merchandise_value DESC
LIMIT 10;

-- Insight: The leading seller generates approximately R$229,472.63 in merchandise value across 1,132 orders.
-- Another seller generates R$222,776.05 across 358 orders, while a third generates R$200,472.92 across 1,806 orders.
-- The top sellers differ in both order volume and merchandise value.

-- Business implication: High merchandise value can come from different business patterns:
-- handling many orders or selling higher-value items. Seller performance should therefore be assessed
-- using multiple metrics rather than sales value alone.

-- Recommendation: Track merchandise value, order volume, and average item price together.
-- Investigate the operating practices of high-performing sellers before using them as benchmarks.


-- Q23. Which sellers handle the highest number of orders?
-- Purpose: Identify sellers with the greatest order volume and compare their merchandise contribution.
-- Analytical note: A seller's order count alone does not indicate the monetary value of those orders.

SELECT
    seller_id,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(*) AS order_items,
    ROUND(SUM(item_price), 2) AS merchandise_value,
    ROUND(AVG(item_price), 2) AS avg_item_price
FROM vw_order_item_detail
GROUP BY seller_id
ORDER BY total_orders DESC
LIMIT 10;

-- Insight: The leading seller handles 1,854 orders, followed by sellers with 1,806 and 1,706 orders.
-- However, the seller handling 1,854 orders generates R$123,304.83 in merchandise value, while the seller
-- handling 1,806 orders generates R$200,472.92.

-- Business implication: High order volume does not necessarily translate into high merchandise value.
-- Differences in product prices and order composition can explain why sellers with similar order volumes generate different sales totals.

-- Recommendation: Segment sellers by order volume and merchandise value. Use this segmentation to identify high-volume
-- sellers, high-value sellers, and sellers performing strongly on both measures.


-- Q24. Which product categories have the highest average item prices?
-- Purpose: Rank product categories by average item price while considering sample volume and total merchandise value.
-- Analytical note: The minimum item-count threshold reduces the influence of categories with very few observations.

SELECT
    product_category_name,
    COUNT(*) AS order_item_count,
    COUNT(DISTINCT order_id) AS distinct_orders,
    ROUND(AVG(item_price), 2) AS avg_item_price,
    ROUND(SUM(item_price), 2) AS merchandise_value
FROM vw_order_item_detail
GROUP BY product_category_name
HAVING COUNT(*) >= 100
ORDER BY avg_item_price DESC
LIMIT 10;

-- Insight: The pcs category has the highest average item price at R$1,098.34, followed by eletrodomesticos_2 at R$476.12 and agro_industria_e_comercio at R$342.12.
-- The pcs category generates R$222,963.13 in merchandise value from 203 order items.

-- Business implication: Certain categories contribute higher-value items, making their pricing, availability,
-- and seller performance important to monitor. However, a high average price does not automatically mean high profitability.

-- Recommendation: Analyze high-priced categories separately from high-volume categories.
-- Compare their order counts, merchandise value, freight costs, and review scores to understand their overall business contribution.


-- Q25. How concentrated is merchandise value among the top 10 sellers?
-- Purpose: Measure the combined merchandise value of the highest-ranked sellers relative to the overall total.
-- Analytical note: DENSE_RANK assigns the same rank to sellers with tied merchandise values.
-- Consequently, rank ties can cause more than ten sellers to be included in the calculation.

WITH seller_sales AS (
    SELECT
        seller_id,
        SUM(item_price) AS merchandise_value
    FROM vw_order_item_detail
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        seller_id,
        merchandise_value,
        DENSE_RANK() OVER (
            ORDER BY merchandise_value DESC
        ) AS seller_rank
    FROM seller_sales
),
total_sales AS (
    SELECT SUM(merchandise_value) AS total_merchandise_value
    FROM seller_sales
)
SELECT
    COUNT(*) AS top_10_seller_count,
    ROUND(SUM(r.merchandise_value), 2) AS top_10_merchandise_value,
    ROUND(MAX(t.total_merchandise_value), 2) AS overall_merchandise_value,
    ROUND(
        100.0 * SUM(r.merchandise_value)
        / NULLIF(MAX(t.total_merchandise_value), 0),
        2
    ) AS top_10_sales_share_pct
FROM ranked_sellers r
CROSS JOIN total_sales t
WHERE r.seller_rank <= 10;

-- Insight: The top 10 sellers collectively generate approximately R$1.79 million, representing 13.15% of total merchandise
-- value of R$13.59 million.

-- Business implication: Merchandise value is distributed across a broad seller base rather than being dominated
-- by only ten sellers. This can reduce dependence on a small group, although the performance and reliability of individual sellers still matter.

-- Recommendation: Maintain a diversified seller network while identifying high-performing partners for closer performance
-- monitoring and collaboration.


-- Q26. Which sellers have the highest average merchandise value per order?
-- Purpose: Compare seller-level merchandise value per order among sellers with a minimum order volume.
-- Analytical note: The denominator counts distinct orders, preventing multiple item rows in one order
-- from being counted as separate orders.

SELECT
    seller_id,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(item_price), 2) AS merchandise_value,
    ROUND(
        SUM(item_price) / NULLIF(COUNT(DISTINCT order_id), 0),
        2
    ) AS merchandise_value_per_order
FROM vw_order_item_detail
GROUP BY seller_id
HAVING COUNT(DISTINCT order_id) >= 50
ORDER BY merchandise_value_per_order DESC
LIMIT 10;

-- Insight: The leading seller in this ranking averages R$895.75 per order across 57 orders, followed by sellers averaging R$857.48 across 56 orders and R$683.81 across 75 orders.
-- These sellers meet the minimum threshold of 50 orders, making the comparison more meaningful than ranking every seller regardless of order count.

-- Business implication: Some sellers consistently handle orders with higher merchandise value.
-- This may reflect product mix or customer purchasing patterns; the results alone do not establish why these orders are more valuable.

-- Recommendation: Compare these sellers' product categories, freight costs, and review scores with those of high-volume
-- sellers. This can help distinguish sellers with high-value orders from those with strong overall sales volume.


-- =======================================================================================
-- Business Risk & Exception Analysis
-- ===========================================================================================

-- Q27. Which months have the highest cancellation rates?
-- Purpose: Identify purchase months with elevated cancellation rates.
-- Analytical note: The rate is calculated as canceled orders divided by all orders in each month.
-- The minimum monthly order threshold helps limit the influence of very small groups.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END)
        AS canceled_orders,
    ROUND(
        100.0 * SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS cancellation_rate_pct
FROM olist_orders_dataset
WHERE order_purchase_timestamp > '1000-01-01'
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
HAVING COUNT(*) >= 100
ORDER BY cancellation_rate_pct DESC
LIMIT 10;

-- Insight: October 2016 has the highest cancellation rate at 7.41%, with 24 cancellations out of 324 orders.
-- The next-highest rate is August 2018 at 1.29%.

-- Business implication: October 2016 stands out as an early operational exception.
-- However, its small order volume means the rate may be volatile. Investigate the reasons for those cancellations
-- before concluding that cancellation performance improved significantly in later months.


-- Q28. Which months have the highest proportion of unavailable orders?
-- Purpose: Identify periods when orders were most frequently marked unavailable.
-- Analytical note: The percentage uses all orders in the month as its denominator,
-- making it possible to compare months with different order volumes.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'unavailable' THEN 1 ELSE 0 END)
        AS unavailable_orders,
    ROUND(
        100.0 * SUM(CASE WHEN order_status = 'unavailable' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS unavailable_rate_pct
FROM olist_orders_dataset
WHERE order_purchase_timestamp > '1000-01-01'
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
HAVING COUNT(*) >= 100
ORDER BY unavailable_rate_pct DESC
LIMIT 10;

-- Insight: February 2017 has the highest unavailable-order rate at 2.53%, followed by October 2016 at 2.16%.
-- February 2017 recorded 45 unavailable orders out of 1,780.

-- Business implication: Unavailable orders may indicate inventory, listing, or fulfillment problems.
-- Investigating the affected products and sellers could help identify recurring stock-availability issues and
-- reduce unsuccessful orders.


-- Q29. Which delivered orders experienced the most extreme delays?
-- Purpose: Surface delivered orders with the largest positive delays against their estimated delivery dates.
-- Analytical note: Positive days_late indicates delivery after the estimate; extreme values should be validated
-- against source timestamps before being treated as confirmed logistics failures.

SELECT
    order_id,
    customer_state,
    order_purchase_timestamp,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    ROUND(delivery_days, 2) AS delivery_days,
    delivery_vs_estimate_days AS days_late,
    average_review_score
FROM vw_order_summary
WHERE order_status = 'delivered'
  AND delivery_vs_estimate_days > 0
ORDER BY delivery_vs_estimate_days DESC
LIMIT 20;

-- Insight: The results contain extreme delivery delays. The worst example shown took approximately 208 days,
-- arriving around 188 days after the estimated delivery date. Other displayed orders also experienced delays exceeding 130 days.

-- Business implication: Such delays can severely damage customer trust and increase complaints or refunds.
-- These orders deserve investigation into logistics failures, incorrect delivery records, and exceptional cases.

-- Data-quality caution: The September 2018 delivery dates shown for orders purchased in early 2017 are unusual.
-- Verify the underlying timestamps before treating every extreme delay as a genuine logistics failure.


-- Q30. How much merchandise value is associated with canceled orders?
-- Purpose: Quantify the merchandise value associated with canceled orders and identify those with item records.
-- Analytical note: The sum represents merchandise value recorded in the view, not confirmed financial loss.

SELECT
    COUNT(*) AS canceled_orders,
    SUM(CASE WHEN merchandise_amount > 0 THEN 1 ELSE 0 END)
        AS canceled_orders_with_items,
    ROUND(SUM(merchandise_amount), 2)
        AS associated_merchandise_value,
    ROUND(AVG(merchandise_amount), 2)
        AS avg_merchandise_value_per_canceled_order
FROM vw_order_summary
WHERE order_status = 'canceled';

-- Insight: There are 625 canceled orders, of which 461 have associated item records. Their merchandise value totals R$95,235.27, averaging R$152.38 per canceled order across all 625 cancellations.

-- Business implication: Cancellations involve a meaningful amount of merchandise value.
-- Prioritize investigating high-value canceled orders to understand whether preventable issues are affecting sales opportunities.

-- This amount represents merchandise associated with canceled orders, not confirmed lost revenue.
-- The data does not establish whether payments were collected or refunded.


-- Q31. Which delivered orders have no payment records or zero recorded payment?
-- Purpose: Flag delivered orders whose payment summaries are missing or show a zero payment amount.
-- Analytical note: These are reconciliation exceptions for investigation, not automatic proof that a customer did not pay.

SELECT
    order_id,
    order_purchase_timestamp,
    merchandise_amount,
    payment_record_count,
    payment_amount,
    order_status
FROM vw_order_summary
WHERE order_status = 'delivered'
  AND (
      payment_record_count IS NULL
      OR payment_record_count = 0
      OR payment_amount IS NULL
      OR payment_amount = 0
  )
ORDER BY merchandise_amount DESC
LIMIT 50;

-- Insight: One delivered order appears without any payment record. Its merchandise value is R$134.97,
-- while both payment fields are NULL.

-- Business implication: This is a specific financial reconciliation exception.
-- Check the payment records and order history to determine whether the payment data is missing, the transaction was handled outside the recorded system, or an actual reconciliation problem exists.
-- Do not classify it as an unpaid order until the underlying transaction has been verified.