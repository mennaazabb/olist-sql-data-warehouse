# 02 — Requirements

**Project:** Olist E-Commerce Analytics Platform

## 1. Functional Requirements

| ID | Requirement |
|---|---|
| FR-1 | Load all 9 source files into Bronze as-is, with an audit log (time, rows, duration, status) |
| FR-2 | Cleanse and standardize in Silver (types, trimming, deduplication, NULL rules, category translation) and log rejected rows with a reason |
| FR-3 | Use `customer_unique_id` as customer identity (Decision D6) |
| FR-4 | Build a Star Schema in Gold with surrogate keys and a complete `dim_date` |
| FR-5 | Aggregate items and payments to order level before joining (Decision D2) |
| FR-6 | Implement RFM, Cohort/Retention, and LTV analyses in SQL |
| FR-7 | Power BI dashboard (Executive, Customers, Sales, Logistics) using the Metrics Dictionary, with Row-Level Security |
| FR-8 | One master procedure runs Bronze → Silver → Gold, schedulable via SQL Server Agent |

## 2. Non-Functional Requirements

| ID | Requirement |
|---|---|
| NFR-1 | Idempotent pipeline: running it twice gives identical results |
| NFR-2 | Every procedure uses TRY/CATCH and logs failures |
| NFR-3 | No credentials in Git; analysts read from Gold only |
| NFR-4 | Naming conventions and a header comment on every script |
| NFR-5 | README lets a stranger run the project from scratch |

## 3. Source Systems

| File | Grain | ~Rows | Key |
|---|---|---|---|
| orders | one row per order | 99K | `order_id` |
| order_items | one row per item in an order | 113K | `order_id` + `order_item_id` |
| order_payments | one row per payment | 104K | `order_id` + `payment_sequential` |
| order_reviews | one row per review | 99K | `review_id` (not truly unique) |
| customers | one row per order (approx.) | 99K | `customer_id` |
| products | one row per product | 33K | `product_id` |
| sellers | one row per seller | 3K | `seller_id` |
| geolocation | one row per coordinate | ~1M | none |
| category_translation | one row per category | 71 | `product_category_name` |

*Row counts are approximate; real counts are confirmed at load time in Bronze.*

```
customers ──< orders >── order_payments
                │  └───< order_reviews
                └───< order_items >── products ──> category_translation
                            └──> sellers
geolocation ··· joins on zip prefix only
```

**Expected data-quality issues (verified in Silver):**
- `customer_id` changes per order; the real person is `customer_unique_id`
- Zip prefixes must be loaded as text to keep leading zeros
- Geolocation: heavy duplication, inconsistent city spellings
- Reviews: repeated `review_id`, several reviews per order, line breaks and quotes inside text
- Orders: NULL delivery dates are normal for undelivered orders; some timestamps are illogical
- Payments: a few `not_defined` types and zero values
- Products: NULL categories, categories missing from translation, `lenght` typo in column names
- Portuguese characters require UTF-8

## 4. Acceptance Criteria

| Layer | Criteria |
|---|---|
| **Bronze** | All 9 tables loaded; row counts match source files; Portuguese characters display correctly; re-running gives the same counts; each run logged |
| **Silver** | No duplicate or NULL primary keys; Bronze rows = Silver rows + Rejected rows; no delivery before purchase (except logged rejects); one review per order; one geolocation row per zip prefix |
| **Gold** | Surrogate keys unique; no orphan fact rows; fact grain respected; **total revenue in Gold = total revenue in Silver** (no fan-out); `dim_date` has no gaps |
| **Project** | Every dashboard number reconciles to a SQL query; pipeline runs with one command; README works from scratch; no credentials in the repo |
