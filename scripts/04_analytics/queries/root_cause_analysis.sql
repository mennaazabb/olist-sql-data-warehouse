USE OlistDWH;
GO

-- A. Does the review score move with the late rate over time? (delivered orders, by purchase month)
SELECT d.year_month,
       COUNT(*)                          AS delivered_orders,
       SUM(f.is_late) * 100.0 / COUNT(*) AS late_rate_pct,
       AVG(f.review_score * 1.0)         AS avg_review_score
FROM gold.fact_orders f
JOIN gold.dim_date d ON f.purchase_date_key = d.date_key
WHERE f.is_late IS NOT NULL
GROUP BY d.year_month
HAVING COUNT(*) >= 300
ORDER BY d.year_month;

-- B. How much does the review score drop as the delay grows?
SELECT CASE WHEN delay_days = 0              THEN '0 - on time'
            WHEN delay_days BETWEEN 1 AND 3  THEN '1 - 1 to 3 days late'
            WHEN delay_days BETWEEN 4 AND 7  THEN '2 - 4 to 7 days late'
            ELSE                                  '3 - 8+ days late' END AS delay_bucket,
       COUNT(*)                  AS orders,
       AVG(review_score * 1.0)   AS avg_review_score
FROM gold.fact_orders
WHERE is_late IS NOT NULL AND review_score IS NOT NULL
GROUP BY CASE WHEN delay_days = 0              THEN '0 - on time'
              WHEN delay_days BETWEEN 1 AND 3  THEN '1 - 1 to 3 days late'
              WHEN delay_days BETWEEN 4 AND 7  THEN '2 - 4 to 7 days late'
              ELSE                                  '3 - 8+ days late' END
ORDER BY delay_bucket;

-- C. Where are the late orders concentrated? (states with at least 100 delivered orders)
SELECT c.state,
       COUNT(*)                          AS delivered_orders,
       SUM(f.is_late)                    AS late_orders,
       SUM(f.is_late) * 100.0 / COUNT(*) AS late_rate_pct,
       SUM(f.is_late) * 100.0 / SUM(SUM(f.is_late)) OVER () AS share_of_late_orders_pct
FROM gold.fact_orders f
JOIN gold.dim_customer c ON f.customer_key = c.customer_key
WHERE f.is_late IS NOT NULL
GROUP BY c.state
HAVING COUNT(*) >= 100
ORDER BY late_orders DESC;

-- D. What drove the November 2017 revenue jump: more orders, bigger orders, or more new customers?
WITH monthly AS (
    SELECT d.year_month,
           COUNT(DISTINCT f.order_id) AS orders,
           SUM(f.price)               AS revenue
    FROM gold.fact_order_items f
    JOIN gold.dim_date d ON f.order_date_key = d.date_key
    WHERE f.is_valid_sale = 1
    GROUP BY d.year_month
),
first_orders AS (
    SELECT customer_key, MIN(purchase_date_key) AS first_date_key
    FROM gold.fact_orders
    WHERE is_valid_sale = 1
    GROUP BY customer_key
),
new_customers AS (
    SELECT d.year_month, COUNT(*) AS new_customers
    FROM first_orders fo
    JOIN gold.dim_date d ON fo.first_date_key = d.date_key
    GROUP BY d.year_month
)
SELECT m.year_month, m.orders, m.revenue,
       m.revenue / NULLIF(m.orders, 0) AS avg_order_value,
       n.new_customers
FROM monthly m
LEFT JOIN new_customers n ON m.year_month = n.year_month
ORDER BY m.year_month;