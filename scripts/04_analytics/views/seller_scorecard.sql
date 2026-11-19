USE OlistDWH;
GO

-- analytics.seller_scorecard: one row per seller
-- An order can contain items from several sellers; review and delay are order-level,
-- so each seller is credited with the orders that include their items.
CREATE OR ALTER VIEW analytics.seller_scorecard AS
WITH seller_orders AS (
    SELECT DISTINCT seller_key, order_id
    FROM gold.fact_order_items
    WHERE is_valid_sale = 1
),
sales AS (
    SELECT seller_key,
           COUNT(DISTINCT order_id)                    AS orders,
           SUM(price)                                  AS revenue,
           SUM(freight_value) / NULLIF(SUM(price), 0)  AS freight_ratio
    FROM gold.fact_order_items
    WHERE is_valid_sale = 1
    GROUP BY seller_key
),
quality AS (
    SELECT so.seller_key,
           AVG(fo.review_score * 1.0)                              AS avg_review_score,
           SUM(fo.is_late) * 100.0 / NULLIF(COUNT(fo.is_late), 0)  AS late_rate_pct
    FROM seller_orders so
    JOIN gold.fact_orders fo ON so.order_id = fo.order_id
    GROUP BY so.seller_key
)
SELECT s.seller_key,
       ds.seller_id,
       ds.state,
       s.orders,
       s.revenue,
       q.avg_review_score,
       q.late_rate_pct,
       s.freight_ratio,
       CASE WHEN s.orders < 30                                      THEN 'Too few orders'
            WHEN q.avg_review_score >= 4.3 AND q.late_rate_pct <= 5 THEN 'Top performer'
            WHEN q.avg_review_score <  3.5 OR  q.late_rate_pct >= 15 THEN 'At risk'
            ELSE 'Average' END                                      AS seller_status
FROM sales s
JOIN quality q      ON s.seller_key = q.seller_key
JOIN gold.dim_seller ds ON s.seller_key = ds.seller_key;
GO

-- 1. check: one row per seller (expect: 0)
SELECT COUNT(*) - COUNT(DISTINCT seller_key) AS duplicates FROM analytics.seller_scorecard;

-- 2. top 10 sellers by revenue
SELECT TOP 10 seller_id, state, orders, revenue, avg_review_score, late_rate_pct
FROM analytics.seller_scorecard ORDER BY revenue DESC;

-- 3. how many sellers in each status, and how much revenue they hold
SELECT seller_status, COUNT(*) AS sellers, SUM(revenue) AS revenue
FROM analytics.seller_scorecard
GROUP BY seller_status
ORDER BY revenue DESC;

-- 4. at-risk sellers with the most revenue
SELECT TOP 10 seller_id, state, orders, revenue, avg_review_score, late_rate_pct
FROM analytics.seller_scorecard
WHERE seller_status = 'At risk'
ORDER BY revenue DESC;

USE OlistDWH;
GO
