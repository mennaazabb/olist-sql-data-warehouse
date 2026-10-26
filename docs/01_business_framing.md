# 01 — Business Framing

**Project:** Olist E-Commerce Analytics Platform · SQL Server (Medallion) + Power BI

## 1. Background

Olist is a Brazilian marketplace connecting small merchants to large sales channels. The dataset covers ~100K orders (2016–2018) across 9 related tables.

The Data & Analytics team is asked to replace scattered spreadsheets with one trusted data source, so leadership can understand sales performance, customer behavior, and delivery quality and its effect on customer satisfaction.

**Role:** Analytics Engineer / Data Analyst — build the warehouse, ensure data quality, deliver analytics and a dashboard.

## 2. Stakeholders

| Stakeholder | Cares about | Uses |
|---|---|---|
| CEO / Leadership | Growth and revenue | Executive Summary |
| Sales / Marketing | High-value customers, retention | RFM, Cohort, LTV |
| Operations / Logistics | Delivery delays | Delivery Performance |
| Seller Success | Seller performance | Seller Scorecard |
| Data Team | Reliable, documented data | Data Catalog, Pipeline |

## 3. Business Questions

| # | Question |
|---|---|
| Q1 | What is the monthly trend of revenue and orders? |
| Q2 | Which states and cities drive the most revenue? |
| Q3 | Who are the highest-value customers, and how do we segment them (RFM)? |
| Q4 | What is the repeat-purchase rate, and how does cohort retention look? |
| Q5 | Which product categories earn the most, and which are growing or declining? |
| Q6 | Which payment methods are most used, and do installments raise order value? |
| Q7 | What share of orders is delivered late, and how does it vary by state? |
| Q8 | Does late delivery lower review scores, and by how much? |
| Q9 | Who are the best and worst sellers (revenue, reviews, late rate)? |
| Q10 | Is freight a high share of product price in certain categories? |

## 4. Metrics Dictionary

| Metric | Definition |
|---|---|
| Product Revenue | `SUM(price)`, excluding `canceled` and `unavailable` orders |
| GMV | `SUM(price + freight_value)`, same exclusions |
| Orders | `COUNT(DISTINCT order_id)` |
| AOV | Product Revenue ÷ Orders |
| Active Customers | `COUNT(DISTINCT customer_unique_id)` |
| Repeat Customer Rate | Customers with 2+ orders ÷ all customers |
| RFM | Days since last purchase / number of orders / total spend, per `customer_unique_id` |
| Delivery Days | `DATEDIFF(day, order_purchase_timestamp, order_delivered_customer_date)` |
| Late Delivery Rate | Delivered orders where delivered date > estimated date ÷ all delivered orders |
| Avg Review Score | `AVG(review_score)` |
| Freight Ratio | `SUM(freight_value) / SUM(price)` |

## 5. Key Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Revenue excludes `canceled` and `unavailable`; delivery metrics use `delivered` only | Those orders produced no revenue / no delivery date |
| D2 | Aggregate items and payments to order level **before** joining | Prevents fan-out that multiplies revenue |
| D3 | Revenue comes from `order_items`; `order_payments` is for payment analysis only | `payment_value` differs from `price + freight` (vouchers, interest) |
| D4 | Recency uses a fixed reference date = last purchase date in the data | `GETDATE()` would make every customer look inactive |
| D5 | NULL delivery dates on undelivered orders are expected, not errors | Filter explicitly |
| D6 | Customer identity = `customer_unique_id`, never `customer_id` | `customer_id` changes with every order |

## 6. Scope

**In scope:** Medallion warehouse on SQL Server · Star Schema · automated pipeline with logging and quality checks · SQL analytics (RFM, Cohort, LTV) · Power BI dashboard with RLS · GitHub documentation.

**Out of scope:** machine learning · real-time ingestion · cloud deployment · fixing data at the source.

**Assumptions:** the 9 CSV files are the only source (Full Load first) · currency is BRL · data covers 2016–2018 · analysis reference date = last purchase date.

**Known limitations:** data is anonymized · repeat-customer rate is very low (~3%), limiting retention analysis · geolocation has many duplicates · some timestamps are missing or illogical.
