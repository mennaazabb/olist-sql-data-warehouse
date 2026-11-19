USE OlistDWH;
GO

-- ===== Headline KPIs (valid sales only: is_valid_sale = 1) =====
SELECT SUM(price)                                AS product_revenue,
       SUM(item_total)                           AS gmv,
       COUNT(DISTINCT order_id)                  AS orders,
       SUM(price) / COUNT(DISTINCT order_id)     AS avg_order_value
FROM gold.fact_order_items
WHERE is_valid_sale = 1;

-- ===== Q1: monthly revenue and orders =====
SELECT d.year_month,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.price)               AS revenue
FROM gold.fact_order_items f
JOIN gold.dim_date d ON f.order_date_key = d.date_key
WHERE f.is_valid_sale = 1
GROUP BY d.year_month
ORDER BY d.year_month;

-- ===== Q2: revenue by state =====
SELECT c.state,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.price)               AS revenue
FROM gold.fact_order_items f
JOIN gold.dim_customer c ON f.customer_key = c.customer_key
WHERE f.is_valid_sale = 1
GROUP BY c.state
ORDER BY revenue DESC;

-- ===== Q2: top 10 cities =====
SELECT TOP 10
    c.city,
    c.state,
    COUNT(DISTINCT f.order_id) AS orders,
    SUM(f.price) AS revenue
FROM gold.fact_order_items f
JOIN gold.dim_customer c
    ON f.customer_key = c.customer_key
WHERE f.is_valid_sale = 1
GROUP BY c.city, c.state
ORDER BY revenue DESC;


-- ===== Q4 (simple version): how many orders does each customer have? =====
SELECT orders_per_customer, COUNT(*) AS customers
FROM (
    SELECT customer_key, COUNT(DISTINCT order_id) AS orders_per_customer
    FROM gold.fact_orders
    WHERE is_valid_sale = 1
    GROUP BY customer_key
) x
GROUP BY orders_per_customer
ORDER BY orders_per_customer;

-- ===== Q4 (simple version): repeat customer rate =====
SELECT SUM(CASE WHEN orders_per_customer >= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS repeat_customer_pct
FROM (
    SELECT customer_key, COUNT(DISTINCT order_id) AS orders_per_customer
    FROM gold.fact_order_items
    WHERE is_valid_sale = 1
    GROUP BY customer_key
) x;


-- ===== Q5: top 15 categories by revenue =====
SELECT TOP 15 p.category,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.price)               AS revenue
FROM gold.fact_order_items f
JOIN gold.dim_product p ON f.product_key = p.product_key
WHERE f.is_valid_sale = 1
GROUP BY p.category
ORDER BY revenue DESC;


-- ===== growing or declining =====
WITH monthly_revenue AS (
    SELECT
        p.category,
        d.year_month,
        SUM(f.price) AS revenue
    FROM gold.fact_order_items f
    JOIN gold.dim_product p
        ON f.product_key = p.product_key
    JOIN gold.dim_date d
        ON f.order_date_key = d.date_key
    WHERE f.is_valid_sale = 1
    GROUP BY p.category, d.year_month
),
growth AS (
    SELECT
        category,
        year_month,
        revenue,
        LAG(revenue) OVER (
            PARTITION BY category
            ORDER BY year_month
        ) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    category,
    year_month,
    revenue,
    previous_month_revenue,
    revenue - previous_month_revenue AS revenue_change,
    (revenue - previous_month_revenue) * 100.0
        / NULLIF(previous_month_revenue, 0) AS growth_pct
FROM growth
ORDER BY category, year_month;

-- ===== Q6: payment methods (orders that used each method) =====
SELECT payment_type,
       COUNT(DISTINCT order_id) AS orders_using_method,
       SUM(payment_value)       AS total_payment_value
FROM gold.fact_payments
WHERE is_valid_sale = 1
GROUP BY payment_type
ORDER BY orders_using_method DESC;

-- ===== Q6: installments vs order value =====
SELECT max_installments,
       COUNT(*)           AS orders,
       AVG(payment_total) AS avg_order_value
FROM gold.fact_orders
WHERE is_valid_sale = 1 AND max_installments IS NOT NULL
GROUP BY max_installments
ORDER BY max_installments;

-- ===== Q7: late delivery rate (delivered orders only) =====
SELECT COUNT(*)                          AS delivered_orders,
       SUM(is_late)                      AS late_orders,
       ROUND(SUM(is_late) * 100.0 / COUNT(*),2)   AS late_rate_pct
FROM gold.fact_orders
WHERE is_late IS NOT NULL;

-- ===== Q7: late rate by state (states with at least 100 delivered orders) =====
SELECT c.state,
       COUNT(*)                        AS delivered_orders,
       SUM(f.is_late) * 100.0 / COUNT(*) AS late_rate_pct
FROM gold.fact_orders f
JOIN gold.dim_customer c ON f.customer_key = c.customer_key
WHERE f.is_late IS NOT NULL
GROUP BY c.state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;

-- ===== Q8: does late delivery lower the review score? =====
SELECT is_late,
       COUNT(*)                   AS orders,
       AVG(review_score * 1.0)    AS avg_review_score
FROM gold.fact_orders
WHERE is_late IS NOT NULL AND review_score IS NOT NULL
GROUP BY is_late;

-- =====  Q9: Best and Worst Sellers ===== 
WITH seller_orders AS (
    SELECT DISTINCT
        seller_key,
        order_id
    FROM gold.fact_order_items
    WHERE is_valid_sale = 1
),
seller_revenue AS (
    SELECT
        seller_key,
        SUM(price) AS revenue,
        COUNT(DISTINCT order_id) AS orders
    FROM gold.fact_order_items
    WHERE is_valid_sale = 1
    GROUP BY seller_key
),
seller_performance AS (
    SELECT
        so.seller_key,
        AVG(fo.review_score * 1.0) AS avg_review_score,
        SUM(CAST(fo.is_late AS FLOAT)) * 100.0
            / NULLIF(COUNT(fo.is_late), 0) AS late_rate_pct
    FROM seller_orders so
    JOIN gold.fact_orders fo
        ON so.order_id = fo.order_id
    GROUP BY so.seller_key
)
SELECT
    s.seller_id,
    s.city,
    s.state,
    sr.orders,
    sr.revenue,
    sp.avg_review_score,
    sp.late_rate_pct
FROM seller_revenue sr
JOIN gold.dim_seller s
    ON sr.seller_key = s.seller_key
LEFT JOIN seller_performance sp
    ON sr.seller_key = sp.seller_key
ORDER BY sr.revenue DESC;
-- ===== Q10: freight as a share of product price, by category =====
SELECT TOP 15 p.category,
       SUM(f.freight_value) / NULLIF(SUM(f.price), 0) AS freight_ratio,
       SUM(f.price)                                   AS revenue
FROM gold.fact_order_items f
JOIN gold.dim_product p ON f.product_key = p.product_key
WHERE f.is_valid_sale = 1
GROUP BY p.category
HAVING COUNT(*) >= 100
ORDER BY freight_ratio DESC;