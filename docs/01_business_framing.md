# 01 — Business Framing

**Project:** Olist E-Commerce Analytics Platform (SQL Server Medallion + Power BI)

## Objective
Give leadership, sales, operations, and seller management one trusted source for revenue, customer behavior, delivery quality, and seller performance.

## Stakeholders
| Stakeholder | Decision they make | Dashboard page |
|---|---|---|
| CEO / Leadership | Where to invest for growth | Executive |
| Sales / Marketing | Which customers and categories to target | Sales & Products, Customers |
| Operations | Which carriers and regions to fix | Delivery & Reviews |
| Seller Success | Which sellers need intervention | Sellers |
| Data Team | Whether the numbers can be trusted | About, KPI definitions |

## Business Questions
| ID | Question | Page |
|---|---|---|
| Q1 | Monthly trend of revenue and orders | Executive |
| Q2 | Which states and cities drive revenue | Executive |
| Q3 | Highest-value customers and how to segment them (RFM) | Customers |
| Q4 | Repeat-purchase rate and cohort retention | Customers |
| Q5 | Which categories earn most and which are growing | Sales & Products |
| Q6 | Payment methods and whether installments change order value | Sales & Products |
| Q7 | Share of late orders by state | Delivery & Reviews |
| Q8 | Whether late delivery lowers reviews, and by how much | Delivery & Reviews |
| Q9 | Best and worst sellers | Sellers |
| Q10 | Freight share of price by category | Sales & Products |

## Key Decisions
| ID | Decision |
|---|---|
| D1 | Revenue uses valid items only;canceled and unavailable orders are excluded. |
| D2 | Items and payments are aggregated to order level before joining |
| D3 | Revenue comes from order items, not payments (payments include vouchers and interest) |
| D4 | Recency reference date is the last purchase date in the data |
| D5 | Customer identity is `customer_unique_id`, not `customer_id` |
| D6 | Repeat customers form one segment; other segments use spend and recency quintiles |
| D7 | Seller status covers sellers with valid orders (3,053); 42 registered sellers without orders are excluded |
| D8 | Delivery and review findings are associations, not causes |

## Scope
**In:** Medallion warehouse, star schema in Gold, automated pipeline with logging, RFM / cohort / seller analytics, 6-page dashboard, GitHub documentation.
**Out:** Customer LTV, Row-Level Security, machine learning, real-time ingestion, cloud deployment, incremental load, fixing source data.