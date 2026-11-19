# KPI Definitions

Each KPI below matches the SQL and DAX used in the project. Source tables are in `gold` unless noted.

| KPI | Definition | Source | Question | Page |
|---|---|---|---|---|
| Product Revenue | SUM(price) for valid items (`is_valid_sale = 1`); freight excluded | fact_order_items | Q1, Q2, Q5 | Executive, Sales |
| GMV | SUM(item_total) for valid items | fact_order_items | (reference only) | not shown |
| Orders | Distinct valid orders with at least one item | fact_order_items | Q1 | Executive |
| AOV | Product Revenue ÷ Orders | fact_order_items | Q1 | Executive |
| Active Customers | Distinct customer_unique_id with a valid order containing items | fact_order_items, dim_customer | Q3, Q4 | Customers |
| Repeat Customer Rate | Customers with 2+ orders ÷ Active Customers | fact_orders, dim_customer | Q4 | Customers |
| Avg Order Revenue by Installments | Average items_revenue per order, grouped by max_installments | fact_orders | Q6 | Sales |
| Delivered Orders | Orders with order_status = delivered and is_valid_sale = 1 | fact_orders | Q7 | Delivery |
| Late Delivery Rate | Late delivered orders ÷ Delivered Orders (is_late = 1) | fact_orders | Q7 | Delivery |
| Avg Delivery Days | Average delivery_days for delivered orders | fact_orders | Q7 | Delivery |
| Avg Review (On Time / Late) | Average review_score split by is_late | fact_orders | Q8 | Delivery |
| Review Gap | Avg review (on time) minus avg review (late) | fact_orders | Q8 | Delivery |
| Freight Ratio | SUM(freight_value) ÷ SUM(price), categories with 100+ items sold | fact_order_items, dim_product | Q10 | Sales |
| RFM Segment | Rules in docs/methodology.md | analytics.customer_rfm | Q3 | Customers |
| Seller Status | Rules in docs/methodology.md | analytics.seller_scorecard | Q9 | Sellers |
| At-risk Revenue % | Revenue of At-risk sellers ÷ total scorecard revenue | analytics.seller_scorecard | Q9 | Sellers |

**Notes**
- Revenue comes from order items, not payments (Decision D3).
- Customer identity is customer_unique_id (Decision D5).
- Delivery KPIs use delivered orders only.
- Sellers KPIs use the 3,053 sellers with valid orders.