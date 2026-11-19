--customers
-- 1. duplicate customer_id (expect: no rows)
SELECT customer_id, COUNT(*) AS cnt FROM bronze.customers GROUP BY customer_id HAVING COUNT(*) > 1;

-- 2. NULL key (expect: no rows)
SELECT * FROM bronze.customers WHERE customer_id IS NULL;

-- 3. extra spaces (expect: no rows)
SELECT * FROM bronze.customers WHERE customer_city != TRIM(customer_city) OR customer_state != TRIM(customer_state);

-- 4. state values (expect: 27 clean 2-letter codes)
SELECT DISTINCT customer_state FROM bronze.customers ORDER BY 1;

-- 5. zip length (a length of 4 means a lost leading zero)
SELECT LEN(customer_zip_code_prefix) AS zip_length, COUNT(*) AS cnt FROM bronze.customers GROUP BY LEN(customer_zip_code_prefix);

-- 6. ids vs real customers (validates decision D6)
SELECT COUNT(DISTINCT customer_id) AS customer_ids FROM bronze.customers;
SELECT COUNT(DISTINCT customer_unique_id) AS unique_customers FROM bronze.customers;


--=========================================================================
--sellers
-- 1. duplicate seller_id (expect: no rows)
SELECT seller_id, COUNT(*) AS cnt FROM bronze.sellers GROUP BY seller_id HAVING COUNT(*) > 1;

-- 2. extra spaces (expect: no rows)
SELECT * FROM bronze.sellers WHERE seller_city != TRIM(seller_city) OR seller_state != TRIM(seller_state);

-- 3. state values
SELECT DISTINCT seller_state FROM bronze.sellers ORDER BY 1;

-- 4. city values (scan for junk: digits, symbols, "/")
SELECT DISTINCT seller_city FROM bronze.sellers ORDER BY 1;

-- 5. zip length
SELECT LEN(seller_zip_code_prefix) AS zip_length, COUNT(*) AS cnt FROM bronze.sellers GROUP BY LEN(seller_zip_code_prefix);

--geolocation
-- 1. total rows
SELECT COUNT(*) AS total_rows FROM bronze.geolocation;

-- 2. distinct zip codes (compare with #1 to see the duplication)
SELECT COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zip FROM bronze.geolocation;

-- 3. zip codes with more than one city spelling
SELECT TOP 20 geolocation_zip_code_prefix, COUNT(DISTINCT geolocation_city) AS city_variants
FROM bronze.geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_city) > 1
ORDER BY city_variants DESC;

-- 4. coordinates that fail to convert (expect: no rows)
SELECT TOP 20 * FROM bronze.geolocation WHERE TRY_CAST(geolocation_lat AS FLOAT) IS NULL OR TRY_CAST(geolocation_lng AS FLOAT) IS NULL;

-- 5. zip length
SELECT LEN(geolocation_zip_code_prefix) AS zip_length, COUNT(*) AS cnt FROM bronze.geolocation GROUP BY LEN(geolocation_zip_code_prefix);


--=========================================================================
--orders
-- 1. duplicate order_id (expect: no rows)
SELECT order_id, COUNT(*) AS cnt FROM bronze.orders GROUP BY order_id HAVING COUNT(*) > 1;

-- 2. customer_id should be unique per order (expect: no rows)
SELECT customer_id, COUNT(*) AS cnt FROM bronze.orders GROUP BY customer_id HAVING COUNT(*) > 1;

-- 3. status values
SELECT order_status, COUNT(*) AS cnt FROM bronze.orders GROUP BY order_status ORDER BY cnt DESC;

-- 4. how empty dates were loaded: NULL or empty text?
SELECT COUNT(*) AS null_cnt  FROM bronze.orders WHERE order_delivered_customer_date IS NULL;
SELECT COUNT(*) AS empty_cnt FROM bronze.orders WHERE order_delivered_customer_date = '';

-- 5. purchase dates that fail to convert (expect: no rows)
SELECT * FROM bronze.orders WHERE TRY_CAST(order_purchase_timestamp AS DATETIME2) IS NULL;

-- 6. delivered orders without a delivery date
SELECT order_id, order_status FROM bronze.orders
WHERE order_status = 'delivered' AND (order_delivered_customer_date IS NULL OR order_delivered_customer_date = '');

-- 7. delivered before purchase
SELECT order_id, order_purchase_timestamp, order_delivered_customer_date FROM bronze.orders
WHERE TRY_CAST(order_delivered_customer_date AS DATETIME2) < TRY_CAST(order_purchase_timestamp AS DATETIME2);

-- 8. orders whose customer doesn't exist (expect: no rows)
SELECT o.order_id FROM bronze.orders o LEFT JOIN bronze.customers c ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL;


--=========================================================================
--order_items
-- 1. duplicate key (expect: no rows)
SELECT order_id, order_item_id, COUNT(*) AS cnt FROM bronze.order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1;

-- 2. price NULL, zero or negative
SELECT * FROM bronze.order_items WHERE price IS NULL OR TRY_CAST(price AS DECIMAL(10,2)) <= 0;

-- 3. negative freight
SELECT * FROM bronze.order_items WHERE TRY_CAST(freight_value AS DECIMAL(10,2)) < 0;

-- 4. items whose order doesn't exist (expect: no rows)
SELECT i.order_id FROM bronze.order_items i LEFT JOIN bronze.orders o ON i.order_id = o.order_id WHERE o.order_id IS NULL;

-- 5. items whose product doesn't exist (expect: no rows)
SELECT i.product_id FROM bronze.order_items i LEFT JOIN bronze.products p ON i.product_id = p.product_id WHERE p.product_id IS NULL;


--=========================================================================
--order_payments
-- 1. duplicate key (expect: no rows)
SELECT order_id, payment_sequential, COUNT(*) AS cnt FROM bronze.order_payments GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1;

-- 2. payment types
SELECT payment_type, COUNT(*) AS cnt FROM bronze.order_payments GROUP BY payment_type ORDER BY cnt DESC;

-- 3. zero payment value
SELECT * FROM bronze.order_payments WHERE TRY_CAST(payment_value AS DECIMAL(10,2)) = 0;

-- 4. zero installments
SELECT * FROM bronze.order_payments WHERE TRY_CAST(payment_installments AS INT) = 0;


--=========================================================================
--order_reviews
-- 1. duplicate review_id
SELECT review_id, COUNT(*) AS cnt FROM bronze.order_reviews GROUP BY review_id HAVING COUNT(*) > 1;

-- 2. orders with more than one review
SELECT order_id, COUNT(*) AS cnt FROM bronze.order_reviews GROUP BY order_id HAVING COUNT(*) > 1;

-- 3. score values (expect only 1 to 5)
SELECT review_score, COUNT(*) AS cnt FROM bronze.order_reviews GROUP BY review_score ORDER BY review_score;

-- 4. answered before created
SELECT * FROM bronze.order_reviews
WHERE TRY_CAST(review_answer_timestamp AS DATETIME2) < TRY_CAST(review_creation_date AS DATETIME2);

--=========================================================================
--products

-- 1. duplicate product_id (expect: no rows)
SELECT product_id, COUNT(*) AS cnt FROM bronze.products GROUP BY product_id HAVING COUNT(*) > 1;

-- 2. products without a category
SELECT COUNT(*) AS no_category FROM bronze.products WHERE product_category_name IS NULL OR TRIM(product_category_name) = '';

-- 3. categories missing from the translation table
SELECT DISTINCT p.product_category_name
FROM bronze.products p
LEFT JOIN bronze.product_category_translation t ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL AND p.product_category_name IS NOT NULL AND p.product_category_name != '';

-- 4. zero weight
SELECT COUNT(*) AS zero_weight FROM bronze.products WHERE TRY_CAST(product_weight_g AS INT) = 0;

--=========================================================================
--product_category_translation

-- 1. rows and duplicates (expect: 71 rows, no duplicates)
SELECT product_category_name, COUNT(*) AS cnt FROM bronze.product_category_translation GROUP BY product_category_name HAVING COUNT(*) > 1;
SELECT COUNT(*) AS total_rows FROM bronze.product_category_translation;

-- 2. extra spaces (expect: no rows)
SELECT * FROM bronze.product_category_translation
WHERE product_category_name != TRIM(product_category_name) OR product_category_name_english != TRIM(product_category_name_english);