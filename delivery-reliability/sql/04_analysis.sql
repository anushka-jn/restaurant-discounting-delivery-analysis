-- ============================================================
-- Phase 4: Analysis
-- P90, not average, leads every measure here. The average
-- reports the experience of the median (fine) user; P90 reports
-- the user who is about to churn.
-- ============================================================

-- B1. Overview
CREATE OR REPLACE TABLE b1_overview AS
SELECT
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time,
    ROUND(100.0 * SUM(sla_breach::INT) / COUNT(*), 1) AS pct_over_40min,
    ROUND(AVG(distance_km) FILTER (WHERE valid_distance), 1) AS avg_distance_km
FROM delivery_features;

CREATE OR REPLACE TABLE b1_by_date AS
SELECT
    order_date,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time
FROM delivery_features
GROUP BY order_date
ORDER BY order_date;

CREATE OR REPLACE TABLE b1_distance_dist AS
SELECT
    distance_band,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time
FROM delivery_features
WHERE valid_distance
GROUP BY distance_band
ORDER BY distance_band;

-- B2. Where it breaks: P90 by traffic x weather, within city tier.
CREATE OR REPLACE TABLE b2_heatmap AS
SELECT
    city_tier,
    traffic_density,
    weather,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time
FROM delivery_features
WHERE city_tier IS NOT NULL AND traffic_density IS NOT NULL AND weather IS NOT NULL
GROUP BY city_tier, traffic_density, weather
HAVING COUNT(*) >= 20;

-- B3. Rider view
CREATE OR REPLACE TABLE b3_rider_rating AS
SELECT
    CASE
        WHEN rider_rating IS NULL THEN 'Unknown'
        WHEN rider_rating < 4.0 THEN '< 4.0'
        WHEN rider_rating < 4.5 THEN '4.0-4.5'
        WHEN rider_rating < 4.8 THEN '4.5-4.8'
        ELSE '4.8+'
    END AS rating_band,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time
FROM delivery_features
GROUP BY rating_band;

CREATE OR REPLACE TABLE b3_vehicle AS
SELECT
    vehicle_type,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time
FROM delivery_features
WHERE vehicle_type IS NOT NULL
GROUP BY vehicle_type
HAVING COUNT(*) >= 30;

CREATE OR REPLACE TABLE b3_vehicle_condition AS
SELECT
    vehicle_condition,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time
FROM delivery_features
WHERE vehicle_condition IS NOT NULL
GROUP BY vehicle_condition
ORDER BY vehicle_condition;

CREATE OR REPLACE TABLE b3_multiple_deliveries AS
SELECT
    multiple_deliveries,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time,
    quantile_cont(time_taken_min, 0.9) AS p90_time
FROM delivery_features
WHERE multiple_deliveries IS NOT NULL
GROUP BY multiple_deliveries
ORDER BY multiple_deliveries;

-- B4. Order type under load + pickup-delay decomposition
CREATE OR REPLACE TABLE b4_order_type_traffic AS
SELECT
    order_type,
    traffic_density,
    COUNT(*) AS n_orders,
    MEDIAN(time_taken_min) AS median_time
FROM delivery_features
WHERE traffic_density IS NOT NULL
GROUP BY order_type, traffic_density
HAVING COUNT(*) >= 20;

CREATE OR REPLACE TABLE b4_delay_decomposition AS
SELECT
    traffic_density,
    COUNT(*) FILTER (WHERE pickup_delay_min IS NOT NULL) AS n_orders,
    ROUND(AVG(pickup_delay_min), 1) AS avg_pickup_delay_min,
    ROUND(AVG(time_taken_min) - AVG(pickup_delay_min), 1) AS avg_transit_min,
    ROUND(AVG(time_taken_min), 1) AS avg_total_min
FROM delivery_features
WHERE traffic_density IS NOT NULL AND pickup_delay_min IS NOT NULL AND pickup_delay_min < 60
GROUP BY traffic_density;

-- B5. Recommendation: condition-combinations driving the majority of breaches
CREATE OR REPLACE TABLE b5_breach_drivers AS
SELECT
    city_tier,
    traffic_density,
    weather,
    COUNT(*) AS n_orders,
    SUM(sla_breach::INT) AS n_breaches,
    ROUND(100.0 * SUM(sla_breach::INT) / COUNT(*), 1) AS pct_breach,
    ROUND(100.0 * SUM(sla_breach::INT) / SUM(SUM(sla_breach::INT)) OVER (), 1) AS pct_of_all_breaches
FROM delivery_features
WHERE city_tier IS NOT NULL AND traffic_density IS NOT NULL AND weather IS NOT NULL
GROUP BY city_tier, traffic_density, weather
HAVING COUNT(*) >= 20
ORDER BY pct_of_all_breaches DESC
LIMIT 15;
