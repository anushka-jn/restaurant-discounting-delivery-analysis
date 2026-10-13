# Discount Dependence Analysis

Which restaurants convert a discount into real order traffic, and which are just subsidizing orders that would have happened anyway?

**139,319 real restaurant listings, 581 cities, 117 cuisines.** Source: Kaggle `anjan46/swiggy-personal`.

## What makes this hard

The raw data is messy in the way real scraped data actually is: ratings arrive as `"4.2"`, `"NEW"`, or blank; review counts as text like `"500+ ratings"` or `"1K+ ratings"`; and the entire discount structure is free text — multiple offers per restaurant concatenated into one string like `"20% OFF UPTO ₹100\nUSE CODE...ABOVE ₹149"`. None of that is directly queryable until it's parsed.

## The pipeline (`sql/`, run in order)

1. `01_staging.sql` — load everything as `VARCHAR`; casting too early silently drops rows.
2. `02_cleaning.sql` — "0" rating → NULL (a new restaurant isn't a restaurant with 0 stars); `"1K+ ratings"` → 1000 with a floor flag.
3. `03_offers.sql` — the centerpiece: a regex parser reverse-engineered from real offer-text samples, extracting discount type, percentage, cap, and minimum order from unstructured strings.
4. `04_features.sql` — price bands, discount-depth bands, and city × cuisine × price-tier peer groups.
5. `05_analysis.sql` — twelve analyses, including the peer-relative Discount Efficiency Index.

## The key method: peer-relative, not absolute

A 30% discount means something different for a premium restaurant in a metro vs. a budget restaurant in a small town. Every restaurant is ranked only against its real peer group (same city, cuisine, price tier) — comparing traction percentile against discount-depth percentile within that group, not across the whole dataset. Peer groups with fewer than 15 restaurants are excluded from this comparison entirely (42% of restaurants) rather than trusted with too little data.

## Findings

- 98.7% of restaurants run at least one live discount — discounting is table stakes, not a differentiator.
- In the two largest price segments (Value, Mid — ~75% of restaurants), traction is statistically flat beyond ~30–50% discount depth.
- **16.5%** of restaurants are "Over-Discounters" (high depth, low traction) — the margin-leakage segment. 29% are "Organic Stars."
- No rating-quality penalty for heavy discounters (avg rating 4.01–4.18 across every depth band).

## Limitations (stated, not hidden)

- Cross-sectional data: struggling restaurants may discount *because* they're struggling, not the reverse. The real test is a randomized offer-depth cap across matched city×cuisine cells.
- Rating count is scraped as a coarse floor (only 15 distinct levels across 139K restaurants) — every traction measure here uses the mean, not the median, because of it.

## Reproducing this

```bash
pip install -r ../requirements.txt
# Download the raw CSV from Kaggle: anjan46/swiggy-personal
# place it at data/raw/swiggy_restaurants.csv
python3 scripts/build_pipeline.py
```

`dashboard/index.html` is the deployed, self-contained interactive dashboard (data embedded, opens directly in any browser).
