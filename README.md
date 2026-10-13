# Restaurant Discounting & Delivery Performance Analysis

Two real-data SQL analyses of a food-delivery marketplace — one on the supply side (do restaurant discounts actually work?), one on the experience side (where does the delivery promise break?). Built entirely in DuckDB SQL, on real, publicly sourced datasets — no simulated numbers.

## The headline findings

- **Cleaned and parsed messy real-world data** — free-text discount codes, inconsistent rating fields, raw GPS coordinates — across **139,319** restaurant listings and **45,584** delivery records using SQL regex and window functions.
- **Identified 16.5%** of non-incremental discounters by ranking restaurants within SQL-defined peer groups (city, cuisine, price tier), revealing demand saturates beyond **30–50%** discount depth.
- **Isolated 2 of 24** traffic-weather conditions driving **36%** of delivery SLA breaches using SQL-based P90 percentile analysis and delay decomposition, rejecting average-based metrics that hid tail-risk failures.

## Repo structure

```
discount-dependence/     Does restaurant discounting actually drive traffic, or just leak margin?
delivery-reliability/    Where does the delivery-time promise actually break?
```

Each half is a self-contained SQL pipeline (staging → cleaning → feature engineering → analysis) plus a deployed interactive dashboard. See each folder's own README for the full methodology, all findings, and stated limitations.

## Data sources (real, not simulated)

| Analysis | Source | Scale |
|---|---|---|
| Discount Dependence | Kaggle `anjan46/swiggy-personal` — real Swiggy restaurant listings | 139,319 restaurants, 581 cities |
| Delivery Reliability | Kaggle `saurabhbadole/zomato-delivery-operations-analytics-dataset` — real Zomato delivery records | 45,584 deliveries |

Raw source CSVs and the DuckDB warehouse files aren't committed to this repo (they're large, regeneratable build artifacts, not source) — see each sub-folder's README for how to pull the same data and rebuild from scratch.

## Tools

SQL (DuckDB) for the entire pipeline — window functions (`PERCENT_RANK`, `NTILE`), regex-based text parsing, `CASE`-based binning, self-joins for peer comparison, percentile functions (`quantile_cont`), `HAVING` to drop statistically thin cells. Python (`duckdb`, `pandas`) only as a thin orchestration layer running the SQL files in order.
