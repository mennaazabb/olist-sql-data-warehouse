/*=============================================================
Script    : proc_run_pipeline.sql
Purpose   : Runs the whole pipeline in order:
            Bronze load -> Silver load -> Quality gates (Silver) 
            -> Gold load (Physical tables refresh) -> Quality gates (Gold).
            Stops with an error if any step or check fails,
            and logs the run in audit.load_log (layer = 'pipeline').
Parameter : @source_path  folder that contains the CSV files
Usage     : EXEC audit.run_pipeline 
                @source_path = N'C:\path\to\your\datasets';
=============================================================*/

USE OlistDWH;
GO

CREATE OR ALTER PROCEDURE audit.run_pipeline
    @source_path NVARCHAR(500)  
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @start DATETIME2 = SYSDATETIME();
    DECLARE @n INT;
    DECLARE @diff DECIMAL(18,2);

    BEGIN TRY
        -- Step 1: Bronze
        EXEC bronze.load_bronze @source_path = @source_path;

        -- Step 2: Silver
        EXEC silver.load_silver;

        -- Step 3: Quality gate (Silver checks; stops the pipeline if one fails)

        -- 3.1 Silver: every order has a customer
        SELECT @n = COUNT(*)
        FROM silver.orders o
        LEFT JOIN silver.customers c ON o.customer_id = c.customer_id
        WHERE c.customer_id IS NULL;
        IF @n > 0 THROW 50010, 'Quality gate failed: Silver orders without a customer.', 1;

        -- 3.2 Silver: every item has an order
        SELECT @n = COUNT(*)
        FROM silver.order_items i
        LEFT JOIN silver.orders o ON i.order_id = o.order_id
        WHERE o.order_id IS NULL;
        IF @n > 0 THROW 50011, 'Quality gate failed: Silver items without an order.', 1;

        -- 3.3 Reconciliation: Bronze orders = Silver orders + rejected orders
        SELECT @n = (SELECT COUNT(*) FROM bronze.orders)
                  - (SELECT COUNT(*) FROM silver.orders)
                  - (SELECT COUNT(*) FROM audit.rejected_records
                     WHERE table_name = 'orders' AND reject_reason NOT LIKE 'delivery_before_purchase%');
        IF @n <> 0 THROW 50012, 'Quality gate failed: Bronze orders <> Silver orders + rejected.', 1;

        -- Step 4: Refresh Gold Layer (Builds physical tables from gold_views and applies indexes)
        EXEC gold.load_gold;

        -- Step 5: Quality gate (Gold checks; runs after the new tables are loaded)

        -- 5.1 Gold: no duplicated orders (no fan-out)
        SELECT @n = COUNT(*) - COUNT(DISTINCT order_id) FROM gold.fact_orders;
        IF @n <> 0 THROW 50013, 'Quality gate failed: duplicated orders in gold.fact_orders.', 1;

        -- 5.2 Gold: revenue equals Silver revenue
        SELECT @diff = ISNULL((SELECT SUM(price) FROM silver.order_items), 0)
                     - ISNULL((SELECT SUM(price) FROM gold.fact_order_items), 0);
        IF @diff <> 0 THROW 50014, 'Quality gate failed: Gold revenue does not match Silver.', 1;

        -- Success
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status)
        VALUES ('pipeline', 'run_pipeline', @start, SYSDATETIME(),
                DATEDIFF(SECOND, @start, SYSDATETIME()), 'SUCCESS');
    END TRY
    BEGIN CATCH
        INSERT INTO audit.load_log (layer, table_name, load_start, load_end, duration_seconds, status, error_message)
        VALUES ('pipeline', 'run_pipeline', @start, SYSDATETIME(),
                DATEDIFF(SECOND, @start, SYSDATETIME()), 'FAILED', LEFT(ERROR_MESSAGE(), 4000));

        THROW;   -- re-raise so the caller sees the failure
    END CATCH;
END;
GO

/*EXEC audit.run_pipeline
                @source_path = N'<path to the datasets folder>';

-- before and after a second run, these counts must be identical
SELECT (SELECT COUNT(*) FROM bronze.orders)       AS bronze_orders,
       (SELECT COUNT(*) FROM silver.orders)       AS silver_orders,
       (SELECT COUNT(*) FROM silver.order_items)  AS silver_items,
       (SELECT COUNT(*) FROM gold.fact_orders)    AS gold_orders;


EXEC audit.run_pipeline @source_path = N'D:\Wrong\Path';

SELECT TOP 1 status, LEFT(error_message, 200) AS error
FROM audit.load_log WHERE layer = 'pipeline' ORDER BY log_id DESC;
*/

