/*
=============================================================
Script  : test_silver.sql
Purpose : Data quality test suite for the Silver layer.
          Each test counts violating rows (0 = PASS).
          Results are logged in audit.test_results.
          Severity ERROR: the procedure raises an error at the end
          (this will stop the pipeline once it is orchestrated).
          Severity WARN : logged only.
Usage   : EXEC audit.run_silver_tests;
Note    : Unique and NOT NULL keys are already enforced by the
          primary keys in ddl_silver.sql.
=============================================================
*/

USE OlistDWH;
GO

IF OBJECT_ID('audit.test_results', 'U') IS NULL
CREATE TABLE audit.test_results (
    test_result_id  INT IDENTITY(1,1) PRIMARY KEY,
    run_time        DATETIME2      NOT NULL,
    layer           NVARCHAR(20)   NOT NULL,
    test_name       NVARCHAR(150)  NOT NULL,
    test_type       NVARCHAR(30)   NOT NULL,   -- reconciliation / relationship / accepted_values / logic / volume
    severity        NVARCHAR(10)   NOT NULL,   -- ERROR / WARN
    failed_rows     INT            NOT NULL,
    status          NVARCHAR(10)   NOT NULL    -- PASS / FAIL
);
GO

CREATE OR ALTER PROCEDURE audit.run_silver_tests
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_time DATETIME2 = SYSDATETIME();

    ---------------------------------------------------------
    -- Volume: tables must not be empty
    ---------------------------------------------------------
    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', t.test_name, 'volume', 'ERROR', t.empty_flag,
           CASE WHEN t.empty_flag = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM (VALUES
        ('customers_not_empty',   CASE WHEN EXISTS (SELECT 1 FROM silver.customers)   THEN 0 ELSE 1 END),
        ('orders_not_empty',      CASE WHEN EXISTS (SELECT 1 FROM silver.orders)      THEN 0 ELSE 1 END),
        ('order_items_not_empty', CASE WHEN EXISTS (SELECT 1 FROM silver.order_items) THEN 0 ELSE 1 END)
    ) t(test_name, empty_flag);

    ---------------------------------------------------------
    -- Reconciliation: Bronze rows = Silver rows + Rejected rows
    ---------------------------------------------------------
    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', t.test_name, 'reconciliation', 'ERROR', t.diff,
           CASE WHEN t.diff = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM (VALUES
        ('reconcile_customers',
         ABS((SELECT COUNT(*) FROM bronze.customers) - (SELECT COUNT(*) FROM silver.customers)
             - (SELECT COUNT(*) FROM audit.rejected_records WHERE table_name = 'customers'))),
        ('reconcile_sellers',
         ABS((SELECT COUNT(*) FROM bronze.sellers) - (SELECT COUNT(*) FROM silver.sellers)
             - (SELECT COUNT(*) FROM audit.rejected_records WHERE table_name = 'sellers'))),
        ('reconcile_products',
         ABS((SELECT COUNT(*) FROM bronze.products) - (SELECT COUNT(*) FROM silver.products)
             - (SELECT COUNT(*) FROM audit.rejected_records WHERE table_name = 'products'))),
        ('reconcile_orders',
         ABS((SELECT COUNT(*) FROM bronze.orders) - (SELECT COUNT(*) FROM silver.orders)
             - (SELECT COUNT(*) FROM audit.rejected_records
                WHERE table_name = 'orders' AND reject_reason NOT LIKE 'delivery_before_purchase%'))),
        ('reconcile_order_items',
         ABS((SELECT COUNT(*) FROM bronze.order_items) - (SELECT COUNT(*) FROM silver.order_items)
             - (SELECT COUNT(*) FROM audit.rejected_records WHERE table_name = 'order_items'))),
        ('reconcile_order_payments',
         ABS((SELECT COUNT(*) FROM bronze.order_payments) - (SELECT COUNT(*) FROM silver.order_payments)
             - (SELECT COUNT(*) FROM audit.rejected_records WHERE table_name = 'order_payments'))),
        ('reconcile_order_reviews',
         ABS((SELECT COUNT(*) FROM bronze.order_reviews) - (SELECT COUNT(*) FROM silver.order_reviews)
             - (SELECT COUNT(*) FROM audit.rejected_records WHERE table_name = 'order_reviews')))
    ) t(test_name, diff);

    ---------------------------------------------------------
    -- Relationships (orphans): child rows without a parent
    ---------------------------------------------------------
    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'orders_have_customer', 'relationship', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.orders o LEFT JOIN silver.customers c ON o.customer_id = c.customer_id
    WHERE c.customer_id IS NULL;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'order_items_have_order', 'relationship', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_items i LEFT JOIN silver.orders o ON i.order_id = o.order_id
    WHERE o.order_id IS NULL;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'order_items_have_product', 'relationship', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_items i LEFT JOIN silver.products p ON i.product_id = p.product_id
    WHERE p.product_id IS NULL;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'order_items_have_seller', 'relationship', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_items i LEFT JOIN silver.sellers s ON i.seller_id = s.seller_id
    WHERE s.seller_id IS NULL;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'order_payments_have_order', 'relationship', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_payments p LEFT JOIN silver.orders o ON p.order_id = o.order_id
    WHERE o.order_id IS NULL;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'order_reviews_have_order', 'relationship', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_reviews r LEFT JOIN silver.orders o ON r.order_id = o.order_id
    WHERE o.order_id IS NULL;

    -- Warning only: a missing translation does not break the numbers
    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'products_have_category_translation', 'relationship', 'WARN', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.products p
    LEFT JOIN silver.product_category_translation t ON p.product_category_name = t.product_category_name
    WHERE t.product_category_name IS NULL;

    ---------------------------------------------------------
    -- Accepted values
    ---------------------------------------------------------
    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'order_status_accepted_values', 'accepted_values', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.orders
    WHERE order_status NOT IN ('delivered','shipped','canceled','unavailable','invoiced','processing','created','approved');

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'review_score_between_1_and_5', 'accepted_values', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_reviews
    WHERE review_score NOT BETWEEN 1 AND 5;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'payment_type_accepted_values', 'accepted_values', 'WARN', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_payments
    WHERE payment_type NOT IN ('credit_card','boleto','voucher','debit_card');   -- 'not_defined' is expected: documented

    ---------------------------------------------------------
    -- Business logic
    ---------------------------------------------------------
    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'delivery_not_before_purchase', 'logic', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.orders
    WHERE order_delivered_customer_date < order_purchase_timestamp;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'item_price_positive', 'logic', 'ERROR', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM silver.order_items
    WHERE price <= 0;

    INSERT INTO audit.test_results (run_time, layer, test_name, test_type, severity, failed_rows, status)
    SELECT @run_time, 'silver', 'zip_codes_have_5_characters', 'logic', 'WARN', COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
    FROM (SELECT customer_zip_code_prefix AS zip FROM silver.customers
          UNION ALL SELECT seller_zip_code_prefix FROM silver.sellers
          UNION ALL SELECT geolocation_zip_code_prefix FROM silver.geolocation) z
    WHERE LEN(zip) != 5;

    ---------------------------------------------------------
    -- Fail loudly if any ERROR-level test failed in this run
    ---------------------------------------------------------
    IF EXISTS (SELECT 1 FROM audit.test_results
               WHERE run_time = @run_time AND severity = 'ERROR' AND status = 'FAIL')
        THROW 50002, 'Silver tests FAILED. See audit.test_results.', 1;
END;
GO