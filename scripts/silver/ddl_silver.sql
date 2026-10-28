/*
=============================================================
Script  : ddl_silver.sql
Purpose : Creates audit.rejected_records and the 9 Silver tables
          with proper data types, primary keys and a technical
          column dwh_create_date.
WARNING : Existing Silver tables are dropped and recreated.
=============================================================
*/

USE OlistDWH;
GO

-- Rejected / corrected rows with the reason
IF OBJECT_ID('audit.rejected_records', 'U') IS NOT NULL DROP TABLE audit.rejected_records;
CREATE TABLE audit.rejected_records (
    reject_id      INT IDENTITY(1,1) PRIMARY KEY,
    table_name     NVARCHAR(100)  NOT NULL,
    record_key     NVARCHAR(200)  NULL,
    reject_reason  NVARCHAR(200)  NOT NULL,
    rejected_at    DATETIME2      NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.customers', 'U') IS NOT NULL DROP TABLE silver.customers;
CREATE TABLE silver.customers (
    customer_id               NVARCHAR(50)  NOT NULL PRIMARY KEY,
    customer_unique_id        NVARCHAR(50)  NOT NULL,
    customer_zip_code_prefix  NVARCHAR(5)   NULL,
    customer_city             NVARCHAR(100) NULL,
    customer_state            NCHAR(2)      NULL,
    dwh_create_date           DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.geolocation', 'U') IS NOT NULL DROP TABLE silver.geolocation;
CREATE TABLE silver.geolocation (
    geolocation_zip_code_prefix  NVARCHAR(5)   NOT NULL PRIMARY KEY,
    geolocation_lat              DECIMAL(9,6)  NULL,
    geolocation_lng              DECIMAL(9,6)  NULL,
    geolocation_city             NVARCHAR(100) NULL,
    geolocation_state            NCHAR(2)      NULL,
    dwh_create_date              DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.orders', 'U') IS NOT NULL DROP TABLE silver.orders;
CREATE TABLE silver.orders (
    order_id                       NVARCHAR(50)  NOT NULL PRIMARY KEY,
    customer_id                    NVARCHAR(50)  NOT NULL,
    order_status                   NVARCHAR(30)  NOT NULL,
    order_purchase_timestamp       DATETIME2(0)  NOT NULL,
    order_approved_at              DATETIME2(0)  NULL,
    order_delivered_carrier_date   DATETIME2(0)  NULL,
    order_delivered_customer_date  DATETIME2(0)  NULL,
    order_estimated_delivery_date  DATETIME2(0)  NULL,
    dwh_create_date                DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.order_items', 'U') IS NOT NULL DROP TABLE silver.order_items;
CREATE TABLE silver.order_items (
    order_id             NVARCHAR(50)  NOT NULL,
    order_item_id        INT           NOT NULL,
    product_id           NVARCHAR(50)  NOT NULL,
    seller_id            NVARCHAR(50)  NOT NULL,
    shipping_limit_date  DATETIME2(0)  NULL,
    price                DECIMAL(10,2) NOT NULL,
    freight_value        DECIMAL(10,2) NOT NULL,
    dwh_create_date      DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_silver_order_items PRIMARY KEY (order_id, order_item_id)
);
GO

IF OBJECT_ID('silver.order_payments', 'U') IS NOT NULL DROP TABLE silver.order_payments;
CREATE TABLE silver.order_payments (
    order_id              NVARCHAR(50)  NOT NULL,
    payment_sequential    INT           NOT NULL,
    payment_type          NVARCHAR(30)  NOT NULL,
    payment_installments  INT           NOT NULL,
    payment_value         DECIMAL(10,2) NOT NULL,
    dwh_create_date       DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_silver_order_payments PRIMARY KEY (order_id, payment_sequential)
);
GO

IF OBJECT_ID('silver.order_reviews', 'U') IS NOT NULL DROP TABLE silver.order_reviews;
CREATE TABLE silver.order_reviews (
    order_id                 NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- one review per order
    review_id                NVARCHAR(50)  NOT NULL,
    review_score             TINYINT       NOT NULL,
    review_comment_title     NVARCHAR(MAX) NULL,
    review_comment_message   NVARCHAR(MAX) NULL,
    review_creation_date     DATETIME2(0)  NULL,
    review_answer_timestamp  DATETIME2(0)  NULL,
    dwh_create_date          DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.products', 'U') IS NOT NULL DROP TABLE silver.products;
CREATE TABLE silver.products (
    product_id                   NVARCHAR(50)  NOT NULL PRIMARY KEY,
    product_category_name        NVARCHAR(100) NOT NULL,
    product_name_length          INT           NULL,
    product_description_length   INT           NULL,
    product_photos_qty           INT           NULL,
    product_weight_g             INT           NULL,
    product_length_cm            INT           NULL,
    product_height_cm            INT           NULL,
    product_width_cm             INT           NULL,
    dwh_create_date              DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.sellers', 'U') IS NOT NULL DROP TABLE silver.sellers;
CREATE TABLE silver.sellers (
    seller_id               NVARCHAR(50)  NOT NULL PRIMARY KEY,
    seller_zip_code_prefix  NVARCHAR(5)   NULL,
    seller_city             NVARCHAR(100) NULL,
    seller_state            NCHAR(2)      NULL,
    dwh_create_date         DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.product_category_translation', 'U') IS NOT NULL DROP TABLE silver.product_category_translation;
CREATE TABLE silver.product_category_translation (
    product_category_name          NVARCHAR(100) NOT NULL PRIMARY KEY,
    product_category_name_english  NVARCHAR(100) NOT NULL,
    dwh_create_date                DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO