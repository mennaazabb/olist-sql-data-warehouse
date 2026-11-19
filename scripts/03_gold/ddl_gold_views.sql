/*=============================================================
Script  : ddl_gold_views.sql
Purpose : Gold layer views (Star Schema) on top of Silver,
          created directly inside the 'gold_views' schema.
          Dimensions: dim_customer, dim_product, dim_seller, dim_date
=============================================================*/

USE OlistDWH;
GO

-- التأكد من إنشاء السكيما إذا لم تكن موجودة
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold_views')
    EXEC('CREATE SCHEMA gold_views');
GO

-- 1. dim_customer: one row per REAL customer (customer_unique_id)
CREATE OR ALTER VIEW gold_views.dim_customer AS
WITH latest AS (
    SELECT c.customer_unique_id,
           c.customer_zip_code_prefix,
           c.customer_city,
           c.customer_state,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.order_purchase_timestamp DESC) AS rn
    FROM silver.customers c
    LEFT JOIN silver.orders o ON c.customer_id = o.customer_id
)
SELECT ROW_NUMBER() OVER (ORDER BY customer_unique_id) AS customer_key,
       customer_unique_id,
       customer_zip_code_prefix AS zip_code,
       customer_city            AS city,
       customer_state           AS state
FROM latest
WHERE rn = 1;
GO

-- 2. dim_product: one row per product, with the English category name
CREATE OR ALTER VIEW gold_views.dim_product AS
SELECT ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
       p.product_id,
       p.product_category_name                              AS category_pt,
       COALESCE(t.product_category_name_english, 'unknown') AS category,
       p.product_weight_g  AS weight_g,
       p.product_length_cm AS length_cm,
       p.product_height_cm AS height_cm,
       p.product_width_cm  AS width_cm,
       p.product_photos_qty AS photos_qty
FROM silver.products p
LEFT JOIN silver.product_category_translation t
       ON p.product_category_name = t.product_category_name;
GO

-- 3. dim_seller: one row per seller
CREATE OR ALTER VIEW gold_views.dim_seller AS
SELECT ROW_NUMBER() OVER (ORDER BY seller_id) AS seller_key,
       seller_id,
       seller_zip_code_prefix AS zip_code,
       seller_city            AS city,
       seller_state           AS state
FROM silver.sellers;
GO

-- 4. dim_date: one row per calendar day
CREATE OR ALTER VIEW gold_views.dim_date AS
WITH bounds AS (
    SELECT DATEFROMPARTS(YEAR(MIN(order_purchase_timestamp)), 1, 1) AS start_date,
           DATEFROMPARTS(YEAR(MAX(COALESCE(order_estimated_delivery_date, order_purchase_timestamp))), 12, 31) AS end_date
    FROM silver.orders
),
numbers AS (
    SELECT TOP ((SELECT DATEDIFF(DAY, start_date, end_date) + 1 FROM bounds))
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
dates AS (
    SELECT DATEADD(DAY, n, (SELECT start_date FROM bounds)) AS full_date
    FROM numbers
)
SELECT CAST(FORMAT(full_date, 'yyyyMMdd') AS INT) AS date_key,
       full_date,
       YEAR(full_date)                            AS year,
       DATEPART(QUARTER, full_date)               AS quarter,
       MONTH(full_date)                           AS month,
       CHOOSE(MONTH(full_date), 'January','February','March','April','May','June',
              'July','August','September','October','November','December') AS month_name,
       FORMAT(full_date, 'yyyy-MM')               AS year_month,
       DAY(full_date)                             AS day,
       (DATEDIFF(DAY, '19000101', full_date) % 7) + 1 AS weekday_number,
       CHOOSE((DATEDIFF(DAY, '19000101', full_date) % 7) + 1,
              'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') AS weekday_name,
       CASE WHEN (DATEDIFF(DAY, '19000101', full_date) % 7) + 1 IN (6, 7) THEN 1 ELSE 0 END AS is_weekend
FROM dates;
GO

-- 5. fact_order_items
CREATE OR ALTER VIEW gold_views.fact_order_items AS
SELECT i.order_id,
       i.order_item_id,
       YEAR(o.order_purchase_timestamp) * 10000
         + MONTH(o.order_purchase_timestamp) * 100
         + DAY(o.order_purchase_timestamp)      AS order_date_key,
       dc.customer_key,
       dp.product_key,
       ds.seller_key,
       o.order_status,
       CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END AS is_valid_sale,
       i.price,
       i.freight_value,
       i.price + i.freight_value                AS item_total
FROM silver.order_items i
JOIN silver.orders        o  ON i.order_id = o.order_id
JOIN silver.customers     c  ON o.customer_id = c.customer_id
JOIN gold_views.dim_customer    dc ON c.customer_unique_id = dc.customer_unique_id
JOIN gold_views.dim_product     dp ON i.product_id = dp.product_id
JOIN gold_views.dim_seller      ds ON i.seller_id = ds.seller_id;
GO

-- 6. fact_orders
CREATE OR ALTER VIEW gold_views.fact_orders AS
WITH items AS (
    SELECT order_id,
           COUNT(*)           AS items_count,
           SUM(price)         AS items_revenue,
           SUM(freight_value) AS freight_total
    FROM silver.order_items
    GROUP BY order_id
),
pay_by_type AS (
    SELECT order_id, payment_type, SUM(payment_value) AS type_value
    FROM silver.order_payments
    GROUP BY order_id, payment_type
),
main_pay AS (
    SELECT order_id, payment_type AS main_payment_type,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY type_value DESC, payment_type) AS rn
    FROM pay_by_type
),
pay AS (
    SELECT order_id,
           COUNT(*)                  AS payment_count,
           SUM(payment_value)        AS payment_total,
           MAX(payment_installments) AS max_installments
    FROM silver.order_payments
    GROUP BY order_id
)
SELECT o.order_id,
       dc.customer_key,
       YEAR(o.order_purchase_timestamp) * 10000 + MONTH(o.order_purchase_timestamp) * 100
         + DAY(o.order_purchase_timestamp)                        AS purchase_date_key,
       YEAR(o.order_delivered_customer_date) * 10000 + MONTH(o.order_delivered_customer_date) * 100
         + DAY(o.order_delivered_customer_date)                   AS delivered_date_key,
       o.order_status,
       CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END AS is_valid_sale,
       CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
            THEN DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date) END AS delivery_days,
       CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
                 AND o.order_estimated_delivery_date IS NOT NULL
            THEN CASE WHEN CAST(o.order_delivered_customer_date AS DATE) > CAST(o.order_estimated_delivery_date AS DATE)
                      THEN 1 ELSE 0 END END                       AS is_late,
       CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
                 AND o.order_estimated_delivery_date IS NOT NULL
            THEN CASE WHEN CAST(o.order_delivered_customer_date AS DATE) > CAST(o.order_estimated_delivery_date AS DATE)
                      THEN DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) ELSE 0 END
            END                                                   AS delay_days,
       r.review_score,
       COALESCE(it.items_count, 0)   AS items_count,
       it.items_revenue,
       it.freight_total,
       p.payment_count,
       p.payment_total,
       p.max_installments,
       mp.main_payment_type
FROM silver.orders o
JOIN silver.customers     c  ON o.customer_id = c.customer_id
JOIN gold_views.dim_customer    dc ON c.customer_unique_id = dc.customer_unique_id
LEFT JOIN silver.order_reviews r  ON o.order_id = r.order_id
LEFT JOIN items               it ON o.order_id = it.order_id
LEFT JOIN pay                 p  ON o.order_id = p.order_id
LEFT JOIN main_pay            mp ON o.order_id = mp.order_id AND mp.rn = 1;
GO

-- 7. fact_payments
CREATE OR ALTER VIEW gold_views.fact_payments AS
SELECT p.order_id,
       p.payment_sequential,
       fo.purchase_date_key,
       fo.customer_key,
       fo.is_valid_sale,
       p.payment_type,
       p.payment_installments,
       p.payment_value
FROM silver.order_payments p
JOIN gold_views.fact_orders fo ON p.order_id = fo.order_id;
GO