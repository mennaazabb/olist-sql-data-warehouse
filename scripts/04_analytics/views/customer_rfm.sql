USE OlistDWH;
GO
-- analytics.customer_rfm: one row per customer with RFM values, scores and segment.
-- Reference date = last purchase date in the data (decision D4), joined once with CROSS JOIN.
CREATE OR ALTER VIEW analytics.customer_rfm AS
WITH ref AS (
    SELECT MAX(d.full_date) AS reference_date
    FROM gold.fact_orders f
    JOIN gold.dim_date d ON f.purchase_date_key = d.date_key
    WHERE f.is_valid_sale = 1
),
base AS (
    SELECT f.customer_key,
           MAX(d.full_date)           AS last_purchase_date,
           COUNT(DISTINCT f.order_id) AS frequency
    FROM gold.fact_orders f
    JOIN gold.dim_date d ON f.purchase_date_key = d.date_key
    WHERE f.is_valid_sale = 1
    GROUP BY f.customer_key
),
money AS (
    SELECT customer_key, SUM(price) AS monetary
    FROM gold.fact_order_items
    WHERE is_valid_sale = 1
    GROUP BY customer_key
),
rfm AS (
    SELECT b.customer_key,
           b.last_purchase_date,
           DATEDIFF(DAY, b.last_purchase_date, r.reference_date) AS recency_days,
           b.frequency,
           m.monetary
    FROM base b
    JOIN money m ON b.customer_key = m.customer_key
    CROSS JOIN ref r
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm
)
SELECT customer_key, last_purchase_date, recency_days, frequency, monetary,
       r_score, m_score,
       CASE WHEN frequency >= 2                THEN 'Repeat Buyers'
            WHEN m_score >= 4 AND r_score >= 3 THEN 'Recent Big Spenders'
            WHEN m_score >= 4                  THEN 'At Risk Big Spenders'
            WHEN r_score >= 4                  THEN 'New Customers'
            WHEN r_score <= 2                  THEN 'Lost'
            ELSE 'Need Attention' END          AS segment
FROM scored;
GO

-- 1. average customer value (historical, not a forecast)
SELECT COUNT(*) AS customers,
       AVG(monetary)        AS avg_customer_revenue,
       AVG(frequency * 1.0) AS avg_orders_per_customer
FROM analytics.customer_rfm;

-- 2. customer value by segment
SELECT segment, COUNT(*) AS customers,
       AVG(monetary) AS avg_customer_revenue, SUM(monetary) AS total_revenue
FROM analytics.customer_rfm
GROUP BY segment ORDER BY avg_customer_revenue DESC;

-- 3. (revenue concentration by decile: unchanged)
WITH ranked AS (
    SELECT monetary, NTILE(10) OVER (ORDER BY monetary DESC) AS decile
    FROM analytics.customer_rfm
)
SELECT decile, COUNT(*) AS customers, SUM(monetary) AS revenue,
       SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER () AS revenue_pct
FROM ranked GROUP BY decile ORDER BY decile;

-- 4. top 20 highest-value customers
SELECT TOP 20 customer_key, frequency, monetary, recency_days, segment
FROM analytics.customer_rfm
ORDER BY monetary DESC, frequency DESC;

