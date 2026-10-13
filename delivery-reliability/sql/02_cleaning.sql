-- ============================================================
-- Phase 2: Cleaning
--
-- Key decisions:
--   * "NaN" arrives as a literal string in several numeric/
--     categorical columns -- converted to real NULL.
--   * Restaurant/delivery latitude carries sign errors (431 rows
--     with a negative Indian latitude, which doesn't exist) --
--     corrected with ABS(). Longitude is unaffected in this file.
--   * Order_Date is DD-MM-YYYY text; Time_Orderd / Time_Order_picked
--     are HH:MM text, parsed to TIME.
--   * The literal ID string doubles as a real city signal: e.g.
--     "INDORES19DEL02" encodes rider city "INDO" (Indore) --
--     something the raw City column (Metropolitian/Urban/Semi-Urban)
--     can't give you.
-- ============================================================

CREATE OR REPLACE TABLE clean_deliveries AS
SELECT
    ID AS order_id,
    Delivery_person_ID AS rider_id,
    regexp_extract(Delivery_person_ID, '^([A-Za-z]+)RES', 1) AS rider_city_code,

    TRY_CAST(NULLIF(Delivery_person_Age, 'NaN') AS INTEGER) AS rider_age,
    TRY_CAST(NULLIF(Delivery_person_Ratings, 'NaN') AS DOUBLE) AS rider_rating,

    ABS(TRY_CAST(Restaurant_latitude AS DOUBLE))         AS restaurant_lat,
    ABS(TRY_CAST(Restaurant_longitude AS DOUBLE))        AS restaurant_lon,
    ABS(TRY_CAST(Delivery_location_latitude AS DOUBLE))  AS delivery_lat,
    ABS(TRY_CAST(Delivery_location_longitude AS DOUBLE)) AS delivery_lon,

    STRPTIME(Order_Date, '%d-%m-%Y')::DATE AS order_date,
    TRY_CAST(NULLIF(Time_Orderd, 'NaN') AS TIME)       AS time_ordered,
    TRY_CAST(NULLIF(Time_Order_picked, 'NaN') AS TIME) AS time_picked,

    NULLIF(Weather_conditions, 'NaN')     AS weather,
    NULLIF(Road_traffic_density, 'NaN')   AS traffic_density,
    TRY_CAST(Vehicle_condition AS INTEGER) AS vehicle_condition,
    Type_of_order   AS order_type,
    Type_of_vehicle AS vehicle_type,
    TRY_CAST(NULLIF(multiple_deliveries, 'NaN') AS INTEGER) AS multiple_deliveries,
    CASE NULLIF(Festival, 'NaN') WHEN 'Yes' THEN TRUE WHEN 'No' THEN FALSE END AS is_festival,
    NULLIF(City, 'NaN') AS city_tier,
    TRY_CAST(regexp_replace("Time_taken (min)", '[^0-9]', '', 'g') AS INTEGER) AS time_taken_min

FROM stg_deliveries
WHERE ID IS NOT NULL;

SELECT COUNT(*) AS clean_row_count FROM clean_deliveries;
