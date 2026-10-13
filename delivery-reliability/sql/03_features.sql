-- ============================================================
-- Phase 2/3: Feature engineering
-- None of these columns exist in the raw file -- they're what
-- turns "45K delivery rows" into an actual reliability analysis.
-- ============================================================

CREATE OR REPLACE TABLE delivery_features AS
WITH base AS (
    SELECT
        *,
        -- Haversine distance (km), restaurant -> drop point.
        2 * 6371 * ASIN(SQRT(
            POWER(SIN(RADIANS(delivery_lat - restaurant_lat) / 2), 2) +
            COS(RADIANS(restaurant_lat)) * COS(RADIANS(delivery_lat)) *
            POWER(SIN(RADIANS(delivery_lon - restaurant_lon) / 2), 2)
        )) AS distance_km,

        -- Pickup delay: kitchen/pickup time vs transit time are owned
        -- by different teams and fixed by different levers.
        CASE
            WHEN time_ordered IS NULL OR time_picked IS NULL THEN NULL
            WHEN time_picked >= time_ordered THEN
                DATE_DIFF('minute', time_ordered, time_picked)
            ELSE
                DATE_DIFF('minute', time_ordered, time_picked) + 1440
        END AS pickup_delay_min,

        CASE
            WHEN time_ordered IS NULL THEN NULL
            ELSE EXTRACT(HOUR FROM time_ordered)
        END AS order_hour,

        DAYOFWEEK(order_date) IN (0, 6) AS is_weekend
    FROM clean_deliveries
)
SELECT
    *,
    (distance_km > 0 AND distance_km <= 50) AS valid_distance,

    CASE
        WHEN distance_km <= 5 THEN '0-5 km'
        WHEN distance_km <= 10 THEN '5-10 km'
        WHEN distance_km <= 15 THEN '10-15 km'
        WHEN distance_km <= 20 THEN '15-20 km'
        ELSE '20+ km'
    END AS distance_band,

    CASE
        WHEN distance_km > 0 AND distance_km <= 50 THEN ROUND(time_taken_min / distance_km, 2)
        ELSE NULL
    END AS time_per_km,

    CASE
        WHEN order_hour BETWEEN 6 AND 10  THEN 'Breakfast'
        WHEN order_hour BETWEEN 11 AND 14 THEN 'Lunch'
        WHEN order_hour BETWEEN 15 AND 17 THEN 'Snacks'
        WHEN order_hour BETWEEN 18 AND 21 THEN 'Dinner'
        ELSE 'Late Night'
    END AS daypart,

    (time_taken_min > 40) AS sla_breach,

    CASE rider_city_code
        WHEN 'AGR' THEN 'Agra' WHEN 'ALH' THEN 'Allahabad' WHEN 'AURG' THEN 'Aurangabad'
        WHEN 'BANG' THEN 'Bangalore' WHEN 'BHP' THEN 'Bhopal' WHEN 'CHEN' THEN 'Chennai'
        WHEN 'COIMB' THEN 'Coimbatore' WHEN 'DEH' THEN 'Dehradun' WHEN 'GOA' THEN 'Goa'
        WHEN 'HYD' THEN 'Hyderabad' WHEN 'INDO' THEN 'Indore' WHEN 'JAP' THEN 'Jaipur'
        WHEN 'KNP' THEN 'Kanpur' WHEN 'KOC' THEN 'Kochi' WHEN 'KOL' THEN 'Kolkata'
        WHEN 'LUDH' THEN 'Ludhiana' WHEN 'MUM' THEN 'Mumbai' WHEN 'MYS' THEN 'Mysore'
        WHEN 'PUNE' THEN 'Pune' WHEN 'RANCHI' THEN 'Ranchi' WHEN 'SUR' THEN 'Surat'
        WHEN 'VAD' THEN 'Vadodara'
        ELSE rider_city_code
    END AS rider_city
FROM base
WHERE time_taken_min IS NOT NULL;

SELECT COUNT(*) FROM delivery_features;
