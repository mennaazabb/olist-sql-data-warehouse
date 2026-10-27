/*
=============================================================
Script  : ddl_bronze.sql
Purpose : Creates the 9 Bronze tables. All columns are NVARCHAR
          so the raw data loads as-is. Types are fixed in Silver.
WARNING : Existing Bronze tables are dropped and recreated.
=============================================================
*/

USE OlistDWH;
GO

IF OBJECT_ID('bronze.customers', 'U') IS NOT NULL DROP TABLE bronze.customers;
CREATE TABLE bronze.customers (
    customer_id               NVARCHAR(50),
    customer_unique_id        NVARCHAR(50),
    customer_zip_code_prefix  NVARCHAR(10),
    customer_city             NVARCHAR(100),
    customer_state            NVARCHAR(10)
);
GO

IF OBJECT_ID('bronze.geolocation', 'U') IS NOT NULL DROP TABLE bronze.geolocation;
CREATE TABLE bronze.geolocation (
    geolocation_zip_code_prefix  NVARCHAR(10),
    geolocation_lat              NVARCHAR(50),
    geolocation_lng              NVARCHAR(50),
    geolocation_city             NVARCHAR(100),
    geolocation_state            NVARCHAR(10)
);
GO

IF OBJECT_ID('bronze.order_items', 'U') IS NOT NULL DROP TABLE bronze.order_items;
CREATE TABLE bronze.order_items (
    order_id             NVARCHAR(50),
    order_item_id        NVARCHAR(10),
    product_id           NVARCHAR(50),
    seller_id            NVARCHAR(50),
    shipping_limit_date  NVARCHAR(50),
    price                NVARCHAR(50),
    freight_value        NVARCHAR(50)
);
GO

IF OBJECT_ID('bronze.order_payments', 'U') IS NOT NULL DROP TABLE bronze.order_payments;
CREATE TABLE bronze.order_payments (
    order_id              NVARCHAR(50),
    payment_sequential    NVARCHAR(10),
    payment_type          NVARCHAR(50),
    payment_installments  NVARCHAR(10),
    payment_value         NVARCHAR(50)
);
GO

IF OBJECT_ID('bronze.order_reviews', 'U') IS NOT NULL DROP TABLE bronze.order_reviews;
CREATE TABLE bronze.order_reviews (
    review_id                NVARCHAR(50),
    order_id                 NVARCHAR(50),
    review_score             NVARCHAR(10),
    review_comment_title     NVARCHAR(MAX),
    review_comment_message   NVARCHAR(MAX),
    review_creation_date     NVARCHAR(50),
    review_answer_timestamp  NVARCHAR(50)
);
GO

IF OBJECT_ID('bronze.orders', 'U') IS NOT NULL DROP TABLE bronze.orders;
CREATE TABLE bronze.orders (
    order_id                       NVARCHAR(50),
    customer_id                    NVARCHAR(50),
    order_status                   NVARCHAR(50),
    order_purchase_timestamp       NVARCHAR(50),
    order_approved_at              NVARCHAR(50),
    order_delivered_carrier_date   NVARCHAR(50),
    order_delivered_customer_date  NVARCHAR(50),
    order_estimated_delivery_date  NVARCHAR(50)
);
GO

IF OBJECT_ID('bronze.products', 'U') IS NOT NULL DROP TABLE bronze.products;
CREATE TABLE bronze.products (
    product_id                   NVARCHAR(50),
    product_category_name        NVARCHAR(100),
    product_name_lenght          NVARCHAR(50),
    product_description_lenght   NVARCHAR(50),
    product_photos_qty           NVARCHAR(50),
    product_weight_g             NVARCHAR(50),
    product_length_cm            NVARCHAR(50),
    product_height_cm            NVARCHAR(50),
    product_width_cm             NVARCHAR(50)
);
GO

IF OBJECT_ID('bronze.sellers', 'U') IS NOT NULL DROP TABLE bronze.sellers;
CREATE TABLE bronze.sellers (
    seller_id                NVARCHAR(50),
    seller_zip_code_prefix   NVARCHAR(10),
    seller_city              NVARCHAR(100),
    seller_state             NVARCHAR(10)
);
GO

IF OBJECT_ID('bronze.product_category_translation', 'U') IS NOT NULL DROP TABLE bronze.product_category_translation;
CREATE TABLE bronze.product_category_translation (
    product_category_name          NVARCHAR(100),
    product_category_name_english  NVARCHAR(100)
);
GO
