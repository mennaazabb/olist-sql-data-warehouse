/*
=============================================================
Script  : proc_load_silver.sql
Purpose : Cleans and loads Bronze -> Silver (full load, idempotent).
          Each table runs in its own transaction and is logged in
          audit.load_log. Rejected or corrected rows are written to
          audit.rejected_records with a reason.
          A failure in one table is logged and the next table still
          loads; the procedure raises an error at the end if any
          table failed.
Usage   : EXEC silver.load_silver;
=============================================================
*/

USE OlistDWH;
GO

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_start DATETIME2 = SYSDATETIME();
    DECLARE @start     DATETIME2;
    DECLARE @rows      INT;

    -- Rejected records are rebuilt on every run
    TRUNCATE TABLE audit.rejected_records;

    -------------------------------------------------------------
    -- 1. customers
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.customers;

        WITH c AS (
            SELECT NULLIF(TRIM(customer_id), '')        AS customer_id,
                   NULLIF(TRIM(customer_unique_id), '') AS customer_unique_id,
                   CASE WHEN NULLIF(TRIM(customer_zip_code_prefix), '') IS NULL THEN NULL
                        ELSE RIGHT('00000' + TRIM(customer_zip_code_prefix), 5) END AS zip,
                   LOWER(NULLIF(TRIM(customer_city), ''))  AS city,
                   UPPER(NULLIF(TRIM(customer_state), '')) AS state,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(customer_id), '')
                                      ORDER BY customer_unique_id) AS rn
            FROM bronze.customers
        )
        SELECT *,
               CASE WHEN customer_id IS NULL        THEN 'missing_customer_id'
                    WHEN customer_unique_id IS NULL THEN 'missing_customer_unique_id'
                    WHEN rn > 1                     THEN 'duplicate_customer_id'
               END AS reject_reason
        INTO #stg_customers FROM c;

        INSERT INTO silver.customers
            (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state)
        SELECT customer_id, customer_unique_id, zip, city, state
        FROM #stg_customers WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'customers', customer_id, reject_reason FROM #stg_customers WHERE reject_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.customers;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'customers', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'customers', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 2. sellers
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.sellers;

        WITH c AS (
            SELECT NULLIF(TRIM(seller_id), '') AS seller_id,
                   CASE WHEN NULLIF(TRIM(seller_zip_code_prefix), '') IS NULL THEN NULL
                        ELSE RIGHT('00000' + TRIM(seller_zip_code_prefix), 5) END AS zip,
                   LOWER(NULLIF(TRIM(seller_city), ''))  AS city,
                   UPPER(NULLIF(TRIM(seller_state), '')) AS state,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(seller_id), '')
                                      ORDER BY seller_zip_code_prefix) AS rn
            FROM bronze.sellers
        )
        SELECT *,
               CASE WHEN seller_id IS NULL THEN 'missing_seller_id'
                    WHEN rn > 1            THEN 'duplicate_seller_id'
               END AS reject_reason
        INTO #stg_sellers FROM c;

        INSERT INTO silver.sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state)
        SELECT seller_id, zip, city, state FROM #stg_sellers WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'sellers', seller_id, reject_reason FROM #stg_sellers WHERE reject_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.sellers;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'sellers', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'sellers', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 3. geolocation  (one row per zip: average coordinates,
    --                  most frequent city/state)
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.geolocation;

        WITH g AS (
            SELECT RIGHT('00000' + TRIM(geolocation_zip_code_prefix), 5) AS zip,
                   TRY_CAST(geolocation_lat AS FLOAT)                    AS lat,
                   TRY_CAST(geolocation_lng AS FLOAT)                    AS lng,
                   LOWER(NULLIF(TRIM(geolocation_city), ''))             AS city,
                   UPPER(NULLIF(TRIM(geolocation_state), ''))            AS state
            FROM bronze.geolocation
            WHERE NULLIF(TRIM(geolocation_zip_code_prefix), '') IS NOT NULL
        ),
        coords AS (
            SELECT zip, AVG(lat) AS lat, AVG(lng) AS lng FROM g GROUP BY zip
        ),
        city_rank AS (
            SELECT zip, city, state,
                   ROW_NUMBER() OVER (PARTITION BY zip ORDER BY COUNT(*) DESC, city) AS rn
            FROM g GROUP BY zip, city, state
        )
        INSERT INTO silver.geolocation
            (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)
        SELECT c.zip, CAST(c.lat AS DECIMAL(9,6)), CAST(c.lng AS DECIMAL(9,6)), r.city, r.state
        FROM coords c
        JOIN city_rank r ON c.zip = r.zip AND r.rn = 1;

        SELECT @rows = COUNT(*) FROM silver.geolocation;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'geolocation', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'geolocation', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 4. product_category_translation
    --    (+ categories known to be missing from the source file)
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.product_category_translation;

        INSERT INTO silver.product_category_translation (product_category_name, product_category_name_english)
        SELECT DISTINCT TRIM(product_category_name), TRIM(product_category_name_english)
        FROM bronze.product_category_translation
        WHERE NULLIF(TRIM(product_category_name), '') IS NOT NULL;

        -- Manual additions for categories that appear in products but not in the file
        INSERT INTO silver.product_category_translation (product_category_name, product_category_name_english)
        SELECT v.pt, v.en
        FROM (VALUES ('pc_gamer', 'pc_gamer'),
                     ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers'),
                     ('unknown', 'unknown')) v(pt, en)
        WHERE NOT EXISTS (SELECT 1 FROM silver.product_category_translation t WHERE t.product_category_name = v.pt);

        SELECT @rows = COUNT(*) FROM silver.product_category_translation;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'product_category_translation', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'product_category_translation', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 5. products
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.products;

        WITH c AS (
            SELECT NULLIF(TRIM(product_id), '') AS product_id,
                   COALESCE(NULLIF(TRIM(product_category_name), ''), 'unknown') AS category,
                   TRY_CAST(NULLIF(TRIM(product_name_lenght), '')        AS INT) AS name_length,
                   TRY_CAST(NULLIF(TRIM(product_description_lenght), '') AS INT) AS description_length,
                   TRY_CAST(NULLIF(TRIM(product_photos_qty), '')         AS INT) AS photos_qty,
                   TRY_CAST(NULLIF(TRIM(product_weight_g), '')           AS INT) AS weight_g,
                   TRY_CAST(NULLIF(TRIM(product_length_cm), '')          AS INT) AS length_cm,
                   TRY_CAST(NULLIF(TRIM(product_height_cm), '')          AS INT) AS height_cm,
                   TRY_CAST(NULLIF(TRIM(product_width_cm), '')           AS INT) AS width_cm,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(product_id), '')
                                      ORDER BY product_category_name) AS rn
            FROM bronze.products
        )
        SELECT *,
               CASE WHEN product_id IS NULL THEN 'missing_product_id'
                    WHEN rn > 1             THEN 'duplicate_product_id'
               END AS reject_reason
        INTO #stg_products FROM c;

        INSERT INTO silver.products
            (product_id, product_category_name, product_name_length, product_description_length,
             product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm)
        SELECT product_id, category, name_length, description_length,
               photos_qty, weight_g, length_cm, height_cm, width_cm
        FROM #stg_products WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'products', product_id, reject_reason FROM #stg_products WHERE reject_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.products;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'products', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'products', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 6. orders
    --    A delivery date earlier than the purchase date is set to
    --    NULL (the order itself is kept) and logged.
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.orders;

        WITH c AS (
            SELECT NULLIF(TRIM(order_id), '')    AS order_id,
                   NULLIF(TRIM(customer_id), '') AS customer_id,
                   LOWER(NULLIF(TRIM(order_status), '')) AS order_status,
                   TRY_CAST(NULLIF(TRIM(order_purchase_timestamp), '')      AS DATETIME2(0)) AS purchase_ts,
                   TRY_CAST(NULLIF(TRIM(order_approved_at), '')             AS DATETIME2(0)) AS approved_ts,
                   TRY_CAST(NULLIF(TRIM(order_delivered_carrier_date), '')  AS DATETIME2(0)) AS carrier_ts,
                   TRY_CAST(NULLIF(TRIM(order_delivered_customer_date), '') AS DATETIME2(0)) AS delivered_ts,
                   TRY_CAST(NULLIF(TRIM(order_estimated_delivery_date), '') AS DATETIME2(0)) AS estimated_ts,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(order_id), '')
                                      ORDER BY order_purchase_timestamp) AS rn
            FROM bronze.orders
        )
        SELECT *,
               CASE WHEN order_id IS NULL     THEN 'missing_order_id'
                    WHEN customer_id IS NULL  THEN 'missing_customer_id'
                    WHEN order_status IS NULL THEN 'missing_order_status'
                    WHEN purchase_ts IS NULL  THEN 'invalid_purchase_timestamp'
                    WHEN rn > 1               THEN 'duplicate_order_id'
               END AS reject_reason,
               CASE WHEN delivered_ts < purchase_ts
                    THEN 'delivery_before_purchase: delivered date set to NULL'
               END AS fix_reason
        INTO #stg_orders FROM c;

        INSERT INTO silver.orders
            (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
             order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date)
        SELECT order_id, customer_id, order_status, purchase_ts, approved_ts, carrier_ts,
               CASE WHEN fix_reason IS NULL THEN delivered_ts END,
               estimated_ts
        FROM #stg_orders WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'orders', order_id, reject_reason FROM #stg_orders WHERE reject_reason IS NOT NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'orders', order_id, fix_reason FROM #stg_orders WHERE reject_reason IS NULL AND fix_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.orders;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'orders', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'orders', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 7. order_items
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.order_items;

        WITH c AS (
            SELECT NULLIF(TRIM(order_id), '')   AS order_id,
                   TRY_CAST(NULLIF(TRIM(order_item_id), '') AS INT) AS order_item_id,
                   NULLIF(TRIM(product_id), '') AS product_id,
                   NULLIF(TRIM(seller_id), '')  AS seller_id,
                   TRY_CAST(NULLIF(TRIM(shipping_limit_date), '') AS DATETIME2(0)) AS shipping_limit_date,
                   TRY_CAST(NULLIF(TRIM(price), '')         AS DECIMAL(10,2)) AS price,
                   TRY_CAST(NULLIF(TRIM(freight_value), '') AS DECIMAL(10,2)) AS freight_value,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(order_id), ''), TRY_CAST(NULLIF(TRIM(order_item_id), '') AS INT)
                                      ORDER BY price) AS rn
            FROM bronze.order_items
        )
        SELECT *,
               CASE WHEN order_id IS NULL OR order_item_id IS NULL THEN 'missing_key'
                    WHEN product_id IS NULL OR seller_id IS NULL   THEN 'missing_product_or_seller'
                    WHEN price IS NULL                             THEN 'invalid_price'
                    WHEN price < 0                                 THEN 'negative_price'
                    WHEN freight_value IS NULL                     THEN 'invalid_freight_value'
                    WHEN freight_value < 0                         THEN 'negative_freight_value'
                    WHEN rn > 1                                    THEN 'duplicate_order_item'
               END AS reject_reason
        INTO #stg_order_items FROM c;

        INSERT INTO silver.order_items
            (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value)
        SELECT order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value
        FROM #stg_order_items WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'order_items', CONCAT(order_id, '|', order_item_id), reject_reason FROM #stg_order_items WHERE reject_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.order_items;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'order_items', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'order_items', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 8. order_payments
    --    'not_defined' types and zero values are kept (documented).
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.order_payments;

        WITH c AS (
            SELECT NULLIF(TRIM(order_id), '') AS order_id,
                   TRY_CAST(NULLIF(TRIM(payment_sequential), '')   AS INT) AS payment_sequential,
                   LOWER(NULLIF(TRIM(payment_type), ''))                   AS payment_type,
                   TRY_CAST(NULLIF(TRIM(payment_installments), '') AS INT) AS payment_installments,
                   TRY_CAST(NULLIF(TRIM(payment_value), '') AS DECIMAL(10,2)) AS payment_value,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(order_id), ''), TRY_CAST(NULLIF(TRIM(payment_sequential), '') AS INT)
                                      ORDER BY payment_value) AS rn
            FROM bronze.order_payments
        )
        SELECT *,
               CASE WHEN order_id IS NULL OR payment_sequential IS NULL THEN 'missing_key'
                    WHEN payment_type IS NULL                           THEN 'missing_payment_type'
                    WHEN payment_installments IS NULL                   THEN 'invalid_installments'
                    WHEN payment_value IS NULL OR payment_value < 0     THEN 'invalid_payment_value'
                    WHEN rn > 1                                         THEN 'duplicate_payment'
               END AS reject_reason
        INTO #stg_order_payments FROM c;

        INSERT INTO silver.order_payments
            (order_id, payment_sequential, payment_type, payment_installments, payment_value)
        SELECT order_id, payment_sequential, payment_type, payment_installments, payment_value
        FROM #stg_order_payments WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'order_payments', CONCAT(order_id, '|', payment_sequential), reject_reason FROM #stg_order_payments WHERE reject_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.order_payments;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'order_payments', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'order_payments', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -------------------------------------------------------------
    -- 9. order_reviews  (one review per order: keep the latest)
    -------------------------------------------------------------
    SET @start = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE silver.order_reviews;

        WITH c AS (
            SELECT NULLIF(TRIM(order_id), '')  AS order_id,
                   NULLIF(TRIM(review_id), '') AS review_id,
                   TRY_CAST(NULLIF(TRIM(review_score), '') AS TINYINT) AS review_score,
                   NULLIF(TRIM(review_comment_title), '')   AS comment_title,
                   NULLIF(TRIM(review_comment_message), '') AS comment_message,
                   TRY_CAST(NULLIF(TRIM(review_creation_date), '')    AS DATETIME2(0)) AS creation_ts,
                   TRY_CAST(NULLIF(TRIM(review_answer_timestamp), '') AS DATETIME2(0)) AS answer_ts,
                   ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(order_id), '')
                                      ORDER BY TRY_CAST(NULLIF(TRIM(review_answer_timestamp), '') AS DATETIME2(0)) DESC,
                                               review_id) AS rn
            FROM bronze.order_reviews
        )
        SELECT *,
               CASE WHEN order_id IS NULL OR review_id IS NULL        THEN 'missing_key'
                    WHEN review_score IS NULL OR review_score NOT BETWEEN 1 AND 5 THEN 'invalid_review_score'
                    WHEN rn > 1                                       THEN 'older_review_for_same_order'
               END AS reject_reason
        INTO #stg_order_reviews FROM c;

        INSERT INTO silver.order_reviews
            (order_id, review_id, review_score, review_comment_title, review_comment_message,
             review_creation_date, review_answer_timestamp)
        SELECT order_id, review_id, review_score, comment_title, comment_message, creation_ts, answer_ts
        FROM #stg_order_reviews WHERE reject_reason IS NULL;

        INSERT INTO audit.rejected_records (table_name, record_key, reject_reason)
        SELECT 'order_reviews', CONCAT(order_id, '|', review_id), reject_reason FROM #stg_order_reviews WHERE reject_reason IS NOT NULL;

        SELECT @rows = COUNT(*) FROM silver.order_reviews;
        COMMIT;

        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, rows_loaded, status)
        VALUES ('silver', 'order_reviews', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), @rows, 'SUCCESS');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('silver', 'order_reviews', @start, SYSDATETIME(), DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
    END CATCH;

    -- Fail loudly if any table failed in this run
    IF EXISTS (SELECT 1 FROM audit.load_log
               WHERE layer = 'silver' AND status = 'FAILED' AND load_start >= @run_start)
        RAISERROR('silver.load_silver finished with errors. See audit.load_log.', 16, 1);
END;
GO