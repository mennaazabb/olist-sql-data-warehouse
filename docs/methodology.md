# Methodology

This document defines how customer segments and seller statuses are assigned. Rules are applied in order; the first match wins. Any change to a rule must be logged in the decision log with its impact on the numbers.

## 1. Customer Segments (RFM, v1)

**Inputs (per `customer_unique_id`, valid orders only):**
- **Frequency:** number of distinct orders.
- **Recency:** days from the customer's last purchase to the reference date (the last purchase date in the data, Decision D4).
- **Spend:** sum of item prices (`price`).

**Scoring:**
- **Recency score:** NTILE(5) over recency days. Score 5 = most recent 20%.
- **Spend score:** NTILE(5) over spend. Score 5 = top 20% by spend.
- Scores are relative to the current customer base. Customers with identical values can fall into different buckets, and boundaries shift when the data changes.

**Rules (first match wins):**

| Order | Segment | Rule |
|---|---|---|
| 1 | Repeat Buyers | Frequency ≥ 2 |
| 2 | Recent Big Spenders | Frequency = 1, spend score ≥ 4 (top 40%), recency score ≥ 3 (most recent 60%) |
| 3 | At Risk Big Spenders | Frequency = 1, spend score ≥ 4 (top 40%), recency score ≤ 2 (oldest 40%) |
| 4 | New Customers | Recency score ≥ 4 (most recent 40%), spend score below 4 |
| 5 | Lost | Recency score ≤ 2 (oldest 40%), spend score below 4 |
| 6 | Need Attention | All others (mid recency, spend score below 4) |

**Why this order matters:** Repeat Buyers are checked first, so a repeat customer with high spend is grouped with the repeat group, not with Big Spenders. The v0 version checked recency before spend, and customers with high spend and mid recency fell into Need Attention. That gap was fixed in v1 (see decision log).

## 2. Seller Status (first match wins)

**Population:** sellers with at least one valid order (3,053). Registered sellers without valid orders (42) are excluded.

| Order | Status | Rule |
|---|---|---|
| 1 | Too Few Orders | Orders < 30 |
| 2 | Top Performer | Avg rating ≥ 4.3 and late rate ≤ 5% |
| 3 | At Risk | Avg rating < 3.5 or late rate ≥ 15% |
| 4 | Average | All remaining sellers |

**Note:** the order matters. A seller with 40 orders, rating 3.2, and late rate 5% is At Risk, because rule 3 is checked before rule 4.

## 3. Decision log

| Version | Change | Reason | Impact |
|---|---|---|---|
| v0 | Initial segmentation with Champions, Loyal, and At Risk Repeat as separate repeat segments | First draft | Champions name implied high spend, which the data did not support |
| v0 → v1 | Repeat customers merged into one segment | Repeat group is small (2,888); sub-segments had no distinct action | Three segments became one (Repeat Buyers) |
| v0 → v1 | Rule order fixed: spend checked before recency | Customers with high spend and mid recency fell into Need Attention | Need Attention dropped from 18.4K to 11.3K; Big Spender segments increased |
| v1 | Recent Big Spenders moved to recency ≥ 3 | Earlier condition left a gap at score 3 | Included in the v0 → v1 fix above |