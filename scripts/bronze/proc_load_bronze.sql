/*
=============================================================
Script    : proc_load_bronze.sql
Purpose   : Loads the 9 Olist CSV files into the Bronze tables.
            Full load: TRUNCATE then BULK INSERT (idempotent).
            Each file has its own row terminator (reviews = CRLF,
            others = LF). Every file is logged in audit.load_log.
            A failure in one file is logged and the next file
            still loads; the procedure raises an error at the
            end if any file failed.
Parameter : @source_path  folder that contains the CSV files
Usage     : EXEC bronze.load_bronze
                @source_path = N'D:\Baraa\olist\olist_dataset';
=============================================================
*/

USE OlistDWH;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze
    @source_path NVARCHAR(500) = N'D:\Baraa\olist\olist_dataset'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_start DATETIME2 = SYSDATETIME();

    -- Mapping: Bronze table <-> source file <-> row terminator
    DECLARE @files TABLE (
        id          INT IDENTITY(1,1),
        table_name  SYSNAME,
        file_name   NVARCHAR(200),
        row_term    NVARCHAR(10)
    );

    INSERT INTO @files (table_name, file_name, row_term) VALUES
        ('customers',                    'olist_customers_dataset.csv',      '0x0a'),
        ('geolocation',                  'olist_geolocation_dataset.csv',    '0x0a'),
        ('order_items',                  'olist_order_items_dataset.csv',    '0x0a'),
        ('order_payments',               'olist_order_payments_dataset.csv', '0x0a'),
        ('order_reviews',                'olist_order_reviews_dataset.csv',  '0x0d0a'),
        ('orders',                       'olist_orders_dataset.csv',         '0x0a'),
        ('products',                     'olist_products_dataset.csv',       '0x0a'),
        ('sellers',                      'olist_sellers_dataset.csv',        '0x0a'),
        ('product_category_translation', 'product_category_name_translation.csv', '0x0a');

    DECLARE @i INT = 1,
            @n INT = (SELECT COUNT(*) FROM @files),
            @table_name SYSNAME,
            @file_name  NVARCHAR(200),
            @row_term   NVARCHAR(10),
            @full_name  NVARCHAR(300),
            @file_path  NVARCHAR(800),
            @sql        NVARCHAR(MAX),
            @rows       INT,
            @load_start DATETIME2;

    WHILE @i <= @n
    BEGIN
        SELECT @table_name = table_name, @file_name = file_name, @row_term = row_term
        FROM @files WHERE id = @i;

        SET @full_name  = N'bronze.' + QUOTENAME(@table_name);
        SET @file_path  = @source_path + N'\' + @file_name;
        SET @load_start = SYSDATETIME();
        SET @rows       = NULL;

        BEGIN TRY
            -- 1) Empty the table (makes the load idempotent)
            SET @sql = N'TRUNCATE TABLE ' + @full_name + N';';
            EXEC sp_executesql @sql;

            -- 2) Load the CSV file (UTF-8, quoted fields, skip header)
            SET @sql = N'BULK INSERT ' + @full_name + N'
                FROM ''' + REPLACE(@file_path, '''', '''''') + N'''
                WITH (
                    FORMAT          = ''CSV'',
                    FIELDQUOTE      = ''"'',
                    FIELDTERMINATOR = '','',
                    ROWTERMINATOR   = ''' + @row_term + N''',
                    FIRSTROW        = 2,
                    CODEPAGE        = ''65001'',
                    TABLOCK
                );';
            EXEC sp_executesql @sql;

            -- 3) Count the loaded rows
            SET @sql = N'SELECT @cnt = COUNT(*) FROM ' + @full_name + N';';
            EXEC sp_executesql @sql, N'@cnt INT OUTPUT', @cnt = @rows OUTPUT;

            INSERT INTO audit.load_log
                (layer, table_name, load_start, load_end, duration_seconds,
                 rows_loaded, status, error_message)
            VALUES
                ('bronze', @table_name, @load_start, SYSDATETIME(),
                 DATEDIFF(SECOND, @load_start, SYSDATETIME()),
                 @rows, 'SUCCESS', NULL);
        END TRY
        BEGIN CATCH
            INSERT INTO audit.load_log
                (layer, table_name, load_start, load_end, duration_seconds,
                 rows_loaded, status, error_message)
            VALUES
                ('bronze', @table_name, @load_start, SYSDATETIME(),
                 DATEDIFF(SECOND, @load_start, SYSDATETIME()),
                 NULL, 'FAILED', LEFT(ERROR_MESSAGE(), 4000));
        END CATCH;

        SET @i += 1;
    END;

    -- Fail loudly if any file failed in this run
    IF EXISTS (SELECT 1 FROM audit.load_log
               WHERE layer = 'bronze' AND status = 'FAILED'
                 AND load_start >= @run_start)
        RAISERROR('bronze.load_bronze finished with errors. See audit.load_log.', 16, 1);
END;
GO

--EXEC bronze.load_bronze @source_path = N'D:\Baraa\olist\olist_dataset';
