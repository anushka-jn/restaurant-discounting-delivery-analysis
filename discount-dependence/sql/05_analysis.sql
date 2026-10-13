-- ============================================================
-- Phase 4: Analysis
-- Peer group = city x primary_cuisine x price_band. Cells with
-- fewer than 15 restaurants are dropped from every peer-relative
-- comparison (A7-A9, A12) -- too thin to trust a percentile on.
-- ============================================================

-- A1. Discount penetration by city (top 25 cities by restaurant count)
CREATE OR REPLACE TABLE a1_penetration_city AS
SELECT
    city,
    COUNT(*) AS restaurant_count,
    ROUND(100.0 * SUM(has_offer::INT) / COUNT(*), 1) AS pct_with_offer
FROM restaurant_features
GROUP BY city
HAVING COUNT(*) >= 50
ORDER BY restaurant_count DESC
LIMIT 25;

-- A2. Discount penetration by cuisine (top 20 cuisines by restaurant count)
CREATE OR REPLACE TABLE a2_penetration_cuisine AS
SELECT
    primary_cuisine,
    COUNT(*) AS restaurant_count,
    ROUND(100.0 * SUM(has_offer::INT) / COUNT(*), 1) AS pct_with_offer
FROM restaurant_features
WHERE primary_cuisine IS NOT NULL
GROUP BY primary_cuisine
HAVING COUNT(*) >= 100
ORDER BY restaurant_count DESC
LIMIT 20;

-- A3. Depth distribution by price band
CREATE OR REPLACE TABLE a3_depth_by_price_band AS
SELECT
    price_band,
    discount_depth_band,
    COUNT(*) AS restaurant_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY price_band), 1) AS pct_within_band
FROM restaurant_features
GROUP BY price_band, discount_depth_band;

-- A4. Demand-response curve: traction by discount depth, within price band.
-- Cold-start restaurants excluded here -- a brand-new listing's
-- near-zero rating count reflects age, not discount response.
-- AVG, not MEDIAN: rating_count is scraped as a coarse floor
-- (10+, 20+, 50+, 100+, 500+, 1K+, 5K+, 10K+ -- only 15 distinct
-- levels across 140K restaurants), so the median collapses onto
-- the same bucket for almost every group and shows no movement.
-- The mean still reflects how the underlying mix shifts between
-- buckets. Cells under 30 restaurants are dropped as too thin to
-- read a trend from.
CREATE OR REPLACE TABLE a4_demand_response AS
SELECT
    price_band,
    discount_depth_band,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(rating_count), 0) AS mean_rating_count,
    MEDIAN(rating_count) AS median_rating_count
FROM restaurant_features
WHERE NOT cold_start_flag AND rating_count IS NOT NULL
GROUP BY price_band, discount_depth_band
HAVING COUNT(*) >= 30;

-- A5. Saturation detection: incremental traction per additional depth step.
CREATE OR REPLACE TABLE a5_saturation AS
WITH ordered AS (
    SELECT
        price_band,
        discount_depth_band,
        mean_rating_count,
        CASE discount_depth_band
            WHEN 'None' THEN 0 WHEN 'Low' THEN 1 WHEN 'Mid' THEN 2
            WHEN 'High' THEN 3 WHEN 'Very High' THEN 4
        END AS band_rank
    FROM a4_demand_response
)
SELECT
    price_band,
    discount_depth_band,
    band_rank,
    mean_rating_count,
    mean_rating_count - LAG(mean_rating_count) OVER (
        PARTITION BY price_band ORDER BY band_rank
    ) AS incremental_traction
FROM ordered
ORDER BY price_band, band_rank;

-- A6. Rating quality vs discount depth
CREATE OR REPLACE TABLE a6_rating_quality_vs_depth AS
SELECT
    discount_depth_band,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(rating), 2) AS avg_rating
FROM restaurant_features
WHERE rating IS NOT NULL
GROUP BY discount_depth_band;

-- Base population for peer-relative analyses (A7-A9, A12):
-- qualifying peer groups only (n >= 15).
CREATE OR REPLACE TABLE efficiency_base AS
SELECT
    f.*,
    COALESCE(f.rating_count, 0) AS traction,
    COALESCE(f.discount_depth_pct, 0) AS depth_pct,
    pg.n AS peer_group_size
FROM restaurant_features f
JOIN peer_group_sizes pg USING (peer_group_key)
WHERE pg.n >= 15;

CREATE OR REPLACE TABLE efficiency_scored AS
SELECT
    *,
    PERCENT_RANK() OVER (PARTITION BY peer_group_key ORDER BY traction)  AS traction_percentile,
    PERCENT_RANK() OVER (PARTITION BY peer_group_key ORDER BY depth_pct) AS depth_percentile
FROM efficiency_base;

-- A7. Discount Efficiency Index = peer-relative traction percentile
-- minus peer-relative discount-depth percentile.
CREATE OR REPLACE TABLE a7_efficiency_index AS
SELECT
    *,
    ROUND(traction_percentile - depth_percentile, 3) AS efficiency_index
FROM efficiency_scored;

-- A8. Four-quadrant tiering (median split on each percentile, within peer group)
CREATE OR REPLACE TABLE a8_quadrants AS
SELECT
    *,
    CASE
        WHEN depth_percentile < 0.5 AND traction_percentile >= 0.5 THEN 'Organic Star'
        WHEN depth_percentile >= 0.5 AND traction_percentile >= 0.5 THEN 'Efficient Discounter'
        WHEN depth_percentile >= 0.5 AND traction_percentile < 0.5 THEN 'Over-Discounter'
        ELSE 'Struggling'
    END AS quadrant
FROM a7_efficiency_index;

-- A9. Leakage sizing: share of restaurants in the Over-Discounter quadrant
CREATE OR REPLACE TABLE a9_leakage_overall AS
SELECT
    quadrant,
    COUNT(*) AS restaurant_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_scored
FROM a8_quadrants
GROUP BY quadrant;

CREATE OR REPLACE TABLE a9_leakage_by_price_band AS
SELECT
    price_band,
    ROUND(100.0 * SUM((quadrant = 'Over-Discounter')::INT) / COUNT(*), 1) AS pct_over_discounter,
    COUNT(*) AS restaurant_count
FROM a8_quadrants
GROUP BY price_band;

-- A10. Cold-start check: does discount depth help brand-new
-- restaurants (< 20 ratings) actually get their first ratings?
-- "never rated" = rating IS NULL (still on the "0"/no-rating sentinel).
CREATE OR REPLACE TABLE a10_cold_start_check AS
SELECT
    discount_depth_band,
    COUNT(*) AS restaurant_count,
    ROUND(100.0 * SUM((rating IS NULL)::INT) / COUNT(*), 1) AS pct_never_rated
FROM restaurant_features
WHERE cold_start_flag
GROUP BY discount_depth_band;

-- A11. Offer type mix vs traction (bogo vs percent/flat only), within price band.
-- BOGO turns out vanishingly rare in this dataset (< 0.1% of
-- restaurants) -- that scarcity is itself the finding here, so
-- these small-n rows are kept rather than filtered out.
CREATE OR REPLACE TABLE a11_offer_type_mix AS
SELECT
    price_band,
    COALESCE(has_bogo, FALSE) AS has_bogo_offer,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(rating_count), 0) AS mean_rating_count
FROM restaurant_features
WHERE has_offer AND NOT cold_start_flag
GROUP BY price_band, has_bogo_offer;

-- A12. Final recommendation table: peer-group cells to cap discount depth in.
CREATE OR REPLACE TABLE a12_recommendation AS
SELECT
    peer_group_key,
    COUNT(*) AS restaurant_count,
    ROUND(100.0 * SUM((quadrant = 'Over-Discounter')::INT) / COUNT(*), 1) AS pct_over_discounter,
    ROUND(AVG(depth_pct), 1) AS avg_discount_depth_pct
FROM a8_quadrants
GROUP BY peer_group_key
HAVING COUNT(*) >= 15
ORDER BY pct_over_discounter DESC, restaurant_count DESC
LIMIT 30;
