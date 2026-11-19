USE OlistDWH;
GO

-- analytics.cohort_retention: one row per (cohort month, months since first purchase)
CREATE OR ALTER VIEW analytics.cohort_retention AS
WITH orders_m AS (
    SELECT f.customer_key,
           DATEFROMPARTS(d.year, d.month, 1) AS order_month
    FROM gold.fact_orders f
    JOIN gold.dim_date d ON f.purchase_date_key = d.date_key
    WHERE f.is_valid_sale = 1
),
first_m AS (
    SELECT customer_key, MIN(order_month) AS cohort_month
    FROM orders_m
    GROUP BY customer_key
),
activity AS (
    SELECT DISTINCT o.customer_key,
           fm.cohort_month,
           DATEDIFF(MONTH, fm.cohort_month, o.order_month) AS months_since_first
    FROM orders_m o
    JOIN first_m fm ON o.customer_key = fm.customer_key
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_m
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       a.months_since_first,
       cs.cohort_customers,
       COUNT(DISTINCT a.customer_key)                                  AS active_customers,
       COUNT(DISTINCT a.customer_key) * 100.0 / cs.cohort_customers    AS retention_pct
FROM activity a
JOIN cohort_size cs ON a.cohort_month = cs.cohort_month
GROUP BY a.cohort_month, a.months_since_first, cs.cohort_customers;
GO

-- 1. check: month 0 must be 100% for every cohort (expect: no rows)
SELECT * FROM analytics.cohort_retention WHERE months_since_first = 0 AND retention_pct <> 100;

-- 2. the cohort table (cohorts with at least 1000 customers, first 6 months)
SELECT cohort_month, cohort_customers, months_since_first, CAST(retention_pct AS DECIMAL(5,2)) AS retention_pct
FROM analytics.cohort_retention
WHERE cohort_customers >= 1000 AND months_since_first BETWEEN 0 AND 6
ORDER BY cohort_month, months_since_first;

-- 3. average retention by month since first purchase (the headline number)
SELECT months_since_first,
       SUM(active_customers) * 100.0 / SUM(cohort_customers) AS avg_retention_pct
FROM analytics.cohort_retention
WHERE cohort_customers >= 1000 AND months_since_first BETWEEN 0 AND 6
GROUP BY months_since_first
ORDER BY months_since_first;