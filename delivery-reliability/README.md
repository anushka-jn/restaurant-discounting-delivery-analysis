# Delivery Reliability Dashboard

Zomato's core promise to a user is a delivery time. The average delivery time hides the actual problem, because the damage is concentrated in the tail — the person who waits 55 minutes is invisible in an average.

**45,584 real order-level delivery records.** Source: Kaggle `saurabhbadole/zomato-delivery-operations-analytics-dataset`.

## The method: lead with P90, never average

Every measure in this analysis is the 90th percentile, not the mean. The average describes the experience of the median (fine) customer; P90 describes the customer who's about to churn. This one framing choice is the difference between a BI chart and a reliability analysis.

## The pipeline (`sql/`, run in order)

1. `01_staging.sql` — load raw, un-cast.
2. `02_cleaning.sql` — fix a real bug in the raw data: some GPS coordinates had a flipped sign (a negative Indian latitude, which doesn't exist).
3. `03_features.sql` — haversine distance computed directly in SQL trigonometry (no library); pickup-delay decomposition splitting total time into kitchen-owned (order→pickup) vs. rider-owned (pickup→drop) segments; a real rider city extracted from the rider's ID string (e.g. `INDORES19DEL02` → Indore).
4. `04_analysis.sql` — the P90 breakdown by traffic × weather × city tier, the delay decomposition, and the breach-driver ranking.

## Findings

- Median delivery time: 26 minutes. **P90: 40 minutes** — a 14-minute reliability tax the average hides entirely.
- **2 of ~24** tracked traffic/weather/city-tier condition combinations (Metro + Jam traffic + Fog/Cloudy) account for **36%** of every SLA breach in the dataset.
- Pickup delay (kitchen-side) is flat at ~10 minutes regardless of traffic. Nearly all of the extra time under bad conditions happens after pickup, on the road — this is a routing/dispatch problem, not a restaurant-operations problem.
- The single strongest predictor of a slow delivery: a rider carrying multiple stacked orders (22 min median for 1 order vs. 48 min for 3 stacked).

## Limitations (stated, not hidden)

- No promised-ETA field exists in the data — only actual delivery duration. This measures duration, not whether a promise was broken.
- Single ~44-day snapshot — can't separate seasonal effects from structural ones.
- Distance is haversine (straight-line), understating real road distance in dense urban grids.

## Reproducing this

```bash
pip install -r ../requirements.txt
# Download the raw CSV from Kaggle: saurabhbadole/zomato-delivery-operations-analytics-dataset
# place it at data/raw/zomato_delivery.csv
python3 scripts/build_pipeline.py
```

`dashboard/index.html` is the deployed, self-contained interactive dashboard (data embedded, opens directly in any browser).
