/*
=============================================================
Script  : proc_load_gold.sql
Purpose : Builds the physical Gold tables (dimensions, then facts)
          from the view logic stored in the gold_views schema.
          Full rebuild, idempotent. Dimensions first because the
          fact views look up the dimension surrogate keys.
Usage   : EXEC gold.load_gold;
=============================================================
*/
USE OlistDWH;
GO


CREATE OR ALTER PROCEDURE gold.load_gold
AS
BEGIN
     SET NOCOUNT ON;
     SET XACT_ABORT ON;
     BEGIN TRY
        BEGIN TRANSACTION;

            -- 1. Drop existing Views first
           /* DROP VIEW IF EXISTS gold.fact_payments;
            DROP VIEW IF EXISTS gold.fact_orders;
            DROP VIEW IF EXISTS gold.fact_order_items;
            DROP VIEW IF EXISTS gold.dim_customer;
            DROP VIEW IF EXISTS gold.dim_product;
            DROP VIEW IF EXISTS gold.dim_seller;
            DROP VIEW IF EXISTS gold.dim_date;*/

            -- 2. Drop physical tables if they already exist 
            DROP TABLE IF EXISTS gold.fact_payments;
            DROP TABLE IF EXISTS gold.fact_orders;
            DROP TABLE IF EXISTS gold.fact_order_items;
            DROP TABLE IF EXISTS gold.dim_customer;
            DROP TABLE IF EXISTS gold.dim_product;
            DROP TABLE IF EXISTS gold.dim_seller;
            DROP TABLE IF EXISTS gold.dim_date;

             -- dimensions
            SELECT * INTO gold.dim_customer FROM gold_views.dim_customer;
            SELECT * INTO gold.dim_product  FROM gold_views.dim_product;
            SELECT * INTO gold.dim_seller   FROM gold_views.dim_seller;
            SELECT * INTO gold.dim_date     FROM gold_views.dim_date;

            CREATE UNIQUE CLUSTERED INDEX cx_dim_customer ON gold.dim_customer(customer_key);
            CREATE INDEX ix_dim_customer_uid               ON gold.dim_customer(customer_unique_id);
            CREATE UNIQUE CLUSTERED INDEX cx_dim_product   ON gold.dim_product(product_key);
            CREATE INDEX ix_dim_product_id                 ON gold.dim_product(product_id);
            CREATE UNIQUE CLUSTERED INDEX cx_dim_seller    ON gold.dim_seller(seller_key);
            CREATE INDEX ix_dim_seller_id                  ON gold.dim_seller(seller_id);
            CREATE UNIQUE CLUSTERED INDEX cx_dim_date      ON gold.dim_date(date_key);

            -- facts
            SELECT * INTO gold.fact_order_items FROM gold_views.fact_order_items;
            SELECT * INTO gold.fact_orders      FROM gold_views.fact_orders;
            SELECT * INTO gold.fact_payments    FROM gold_views.fact_payments;

            CREATE CLUSTERED INDEX cx_fact_order_items ON gold.fact_order_items(order_id, order_item_id);
            CREATE INDEX ix_fact_items_seller          ON gold.fact_order_items(seller_key);
            CREATE INDEX ix_fact_items_customer        ON gold.fact_order_items(customer_key);
            CREATE INDEX ix_fact_items_product         ON gold.fact_order_items(product_key);
            CREATE UNIQUE CLUSTERED INDEX cx_fact_orders ON gold.fact_orders(order_id);
            CREATE INDEX ix_fact_orders_customer         ON gold.fact_orders(customer_key);
            CREATE CLUSTERED INDEX cx_fact_payments      ON gold.fact_payments(order_id, payment_sequential);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

--EXEC gold.load_gold;