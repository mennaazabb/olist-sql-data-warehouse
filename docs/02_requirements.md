# 02 — Requirements

**Project:** Olist E-Commerce Analytics Platform

## Data Sources
| File | Grain | Key | Known issues |
|---|---|---|---|
| orders | one row per order | `order_id` | NULL delivery dates for undelivered orders are normal; some timestamps are illogical |
| order_items | one row per item | `order_id` + `order_item_id` | Basis for revenue |
| order_payments | one row per payment | `order_id` + `payment_sequential` | `not_defined` types, zero values |
| order_reviews | one row per review | `review_id` (not unique) | Multiple reviews per order; line breaks in text |
| customers | one row per order | `customer_id` | Changes per order; use `customer_unique_id` |
| products | one row per product | `product_id` | NULL categories; `lenght` column typo |
| sellers | one row per seller | `seller_id` | None found |
| geolocation | one row per coordinate | none | Heavy duplication; inconsistent city names; not used in Gold |
| category_translation | one row per category | `product_category_name` | Some categories missing |

## Data Quality Rules
| Layer | Rule | Handling |
|---|---|---|
| Bronze | UTF-8 text loads correctly; zip prefixes stay text | Load as-is |
| Silver | No duplicate or NULL primary keys | Logged rejects |
| Silver | No delivery before purchase | Logged rejects, not silently fixed |
| Silver | One review per order; one geolocation row per zip prefix | Dedupe with rule |
| Gold | Revenue in Gold = revenue in Silver | Check query |
| Gold | `dim_date` has no gaps | Check query |

## Integration
- Orders join to items, payments, and reviews on `order_id`.
- Customers join to orders on `customer_key`, which maps to `customer_unique_id`.
- Products join to items on `product_id`; categories join to translation on `product_category_name`.
- Sellers join to items on `seller_id`.
- Geolocation is not joined in Gold.

## Functional Requirements
| ID | Requirement | Priority | Acceptance | Traces to |
|---|---|---|---|---|
| FR-1 | Load all 9 files into Bronze as-is, with audit log | Must | Row counts match source | Q1–Q10 |
| FR-2 | Cleanse in Silver: types, trim, dedupe, NULL rules, translation | Must | Bronze = Silver + logged rejects | Q1–Q10 |
| FR-3 | Gold star schema with surrogate keys and complete `dim_date` | Must | Unique keys, no orphan facts | Q1, Q2, Q5 |
| FR-4 | Aggregate items and payments before joining | Must | Gold revenue = Silver revenue | D2, Q1 |
| FR-5 | Analytics objects: `customer_rfm`, `cohort_retention`, `seller_scorecard` | Must | Totals match KPI definitions | Q3, Q4, Q9 |
| FR-6 | 6-page Power BI dashboard | Must | Every number reconciles to SQL | Q1–Q10 |
| FR-7 | One procedure runs the full pipeline, schedulable via SQL Server Agent | Must | Runs end to end with one command | NFR-2 |

## Non-Functional Requirements
| ID | Requirement | Priority | Acceptance |
|---|---|---|---|
| NFR-1 | Idempotent pipeline | Must | Two runs give identical results |
| NFR-2 | TRY/CATCH and logging in every procedure | Must | Failures logged |
| NFR-3 | No credentials in Git; Power BI reads Gold and analytics only | Must | No direct reads of Bronze or Silver |
| NFR-4 | Naming conventions and header comment on every script | Should | Reviewed |
| NFR-5 | README lets a new user run the project from scratch | Must | Followed end to end on a clean setup |
| NFR-6 | Segment and status rules documented; rule changes logged with impact | Must | Entry in `docs/methodology.md` and decision log |