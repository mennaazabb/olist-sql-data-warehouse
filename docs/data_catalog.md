# Data Catalog — Gold Layer

Gold is a Star Schema materialized as tables in `OlistDWH.gold` by `gold.load_gold`, built from view logic in `gold_views` on top of Silver. Power BI reads these tables and the `analytics` objects only.

```
dim_customer ─┐
dim_product  ─┼──< fact_order_items >── dim_date
dim_seller   ─┘

dim_customer ──< fact_orders >── dim_date
                     │
                     └──< fact_payments   (one row per payment, linked by order_id)
```

**Conventions:** surrogate keys end in `_key`; business keys end in `_id`; flags are `0/1`; date keys are integers in `YYYYMMDD` format and join to `dim_date.date_key`.

---

## Dimensions

### gold.dim_customer
**Grain:** one row per real customer (`customer_unique_id`).
**Note:** a customer can have several `customer_id` values (one per order). Location comes from the customer's most recent order (SCD Type 1).

| Column | Description |
|---|---|
| customer_key | Surrogate key |
| customer_unique_id | Real customer identifier from the source |
| zip_code | Zip code prefix (stored as text) |
| city | City (lowercase) |
| state | State code (2 letters) |

### gold.dim_product
**Grain:** one row per product.

| Column | Description |
|---|---|
| product_key | Surrogate key |
| product_id | Product identifier from the source |
| category_pt | Original category name (Portuguese) |
| category | English category name (`unknown` if not translated) |
| weight_g | Weight in grams |
| length_cm / height_cm / width_cm | Package dimensions in cm |
| photos_qty | Number of photos in the listing |

### gold.dim_seller
**Grain:** one row per seller that has at least one order.

| Column | Description |
|---|---|
| seller_key | Surrogate key |
| seller_id | Seller identifier from the source |
| zip_code | Zip code prefix (stored as text) |
| city | City (lowercase) |
| state | State code (2 letters) |

### gold.dim_date
**Grain:** one row per calendar day, from Jan 1 of the first order year to Dec 31 of the last year in the data.

| Column | Description |
|---|---|
| date_key | `YYYYMMDD` integer key |
| full_date | Calendar date |
| year / quarter / month / day | Date parts |
| month_name | English month name |
| year_month | `yyyy-MM` label (useful for monthly trends) |
| weekday_number | 1 = Monday … 7 = Sunday |
| weekday_name | English weekday name |
| is_weekend | 1 for Saturday and Sunday |

---

## Facts

### gold.fact_order_items
**Grain:** one row per item in an order. Use it for sales, categories, and sellers.

| Column | Description |
|---|---|
| order_id, order_item_id | Business key of the row |
| order_date_key | Purchase date → `dim_date` |
| customer_key | → `dim_customer` |
| product_key | → `dim_product` |
| seller_key | → `dim_seller` |
| order_status | Status of the parent order |
| is_valid_sale | 0 for `canceled` and `unavailable` orders, otherwise 1 |
| price | Item price (BRL), excluding freight |
| freight_value | Freight for the item (BRL) |
| item_total | `price + freight_value` |

### gold.fact_orders
**Grain:** one row per order. Use it for delivery, reviews, and payments.
Items and payments are aggregated to order level **before** joining, so no order is duplicated.

| Column | Description |
|---|---|
| order_id | Business key |
| customer_key | → `dim_customer` |
| purchase_date_key | Purchase date → `dim_date` |
| delivered_date_key | Delivery date → `dim_date` (NULL if not delivered) |
| order_status | Order status |
| is_valid_sale | 0 for `canceled` and `unavailable` orders, otherwise 1 |
| delivery_days | Days from purchase to delivery (delivered orders only) |
| is_late | 1 if delivered after the estimated date, 0 if on time, NULL if not delivered |
| delay_days | Days late (0 if on time; delivered orders only) |
| review_score | Review score 1–5 (one review per order after dedup; NULL if none) |
| items_count | Number of items in the order |
| items_revenue | Sum of item prices (BRL) |
| freight_total | Sum of item freight (BRL) |
| payment_count | Number of payments |
| payment_total | Total paid (BRL) |
| max_installments | Highest installment count among payments |
| main_payment_type | Payment type with the largest value in the order. Not suitable for counting how often each method is used (use `fact_payments`) |

### gold.fact_payments
**Grain:** one row per payment. An order can have several payments (for example credit card plus voucher), so an order can appear under more than one payment type. Use it for payment-method analysis.

| Column | Description |
|---|---|
| order_id, payment_sequential | Business key of the row |
| customer_key | → `dim_customer` |
| purchase_date_key | Purchase date of the order → `dim_date` |
| is_valid_sale | 0 for `canceled` and `unavailable` orders, otherwise 1 |
| payment_type | credit_card, boleto, voucher, debit_card, or not_defined |
| payment_installments | Number of installments |
| payment_value | Amount paid (BRL). Includes vouchers and interest; not used for revenue |

---

## Analytics objects (schema: `analytics`)

| Object | Grain | Purpose |
|---|---|---|
| customer_rfm | one row per customer | RFM values, scores, and segment (Q3) |
| cohort_retention | one row per cohort month and month offset | Repeat purchase by first-purchase month (Q4) |
| seller_scorecard | one row per seller with valid orders | Orders, revenue, rating, late rate, status (Q9) |

`fact_orders` has no seller key. Seller metrics come from `seller_scorecard`, because one order can contain items from several sellers.

---

## Business Questions → Tables

| Question | Tables |
|---|---|
| Q1 Revenue and orders trend | `fact_order_items`, `fact_orders`, `dim_date` |
| Q2 Revenue by state/city | `fact_order_items`, `dim_customer` |
| Q3 Top customers, RFM | `customer_rfm` (analytics) |
| Q4 Repeat rate, cohorts | `cohort_retention` (analytics), `fact_orders` |
| Q5 Categories | `fact_order_items`, `dim_product`, `dim_date` |
| Q6 Payment methods, installments | `fact_payments` (methods), `fact_orders` (installments vs order value) |
| Q7 Late delivery | `fact_orders`, `dim_customer` |
| Q8 Delay vs review score | `fact_orders` |
| Q9 Seller performance | `seller_scorecard` (analytics) |
| Q10 Freight ratio | `fact_order_items`, `dim_product` |

## Metric rules

- Revenue = `SUM(price)` with `is_valid_sale = 1`. GMV = `SUM(item_total)` with `is_valid_sale = 1`.
- Delivery metrics (`delivery_days`, `is_late`, `delay_days`) exist only for delivered orders.
- Do not sum `review_score`; use averages.