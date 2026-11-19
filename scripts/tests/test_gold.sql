USE OlistDWH;
GO

-- 1. fact_order_items rows = silver.order_items rows (difference = 0)
SELECT (SELECT COUNT(*) FROM silver.order_items) - (SELECT COUNT(*) FROM gold.fact_order_items) AS difference;

-- 2. fact_orders rows = silver.orders rows (difference = 0)
SELECT (SELECT COUNT(*) FROM silver.orders) - (SELECT COUNT(*) FROM gold.fact_orders) AS difference;

-- 3. no fan-out: duplicate orders in fact_orders (expect: no rows)
SELECT order_id, COUNT(*) AS cnt FROM gold.fact_orders GROUP BY order_id HAVING COUNT(*) > 1;

-- 4. revenue matches Silver (difference = 0 for all three)
SELECT (SELECT SUM(price) FROM silver.order_items) - (SELECT SUM(price) FROM gold.fact_order_items) AS items_difference;
SELECT (SELECT SUM(price) FROM silver.order_items) - (SELECT SUM(items_revenue) FROM gold.fact_orders) AS orders_difference;
SELECT (SELECT SUM(payment_value) FROM silver.order_payments) - (SELECT SUM(payment_total) FROM gold.fact_orders) AS payments_difference;

-- 5. every date_key in the facts exists in dim_date (expect: no rows)
SELECT DISTINCT f.purchase_date_key FROM gold.fact_orders f
LEFT JOIN gold.dim_date d ON f.purchase_date_key = d.date_key WHERE d.date_key IS NULL;

SELECT DISTINCT f.delivered_date_key FROM gold.fact_orders f
LEFT JOIN gold.dim_date d ON f.delivered_date_key = d.date_key
WHERE f.delivered_date_key IS NOT NULL AND d.date_key IS NULL;

-- 6. delivered orders with a delivery date must have is_late filled (expect: no rows)
SELECT order_id FROM gold.fact_orders
WHERE order_status = 'delivered' AND delivered_date_key IS NOT NULL AND is_late IS NULL;

-- 7. quick sanity: late rate among delivered orders (the real one is around 8%)
SELECT SUM(is_late) * 1.0 / COUNT(is_late) AS late_rate FROM gold.fact_orders WHERE is_late IS NOT NULL;

SELECT (SELECT COUNT(*) FROM silver.order_payments) - (SELECT COUNT(*) FROM gold.fact_payments) AS rows_difference,
       (SELECT SUM(payment_value) FROM silver.order_payments) - (SELECT SUM(payment_value) FROM gold.fact_payments) AS value_difference;