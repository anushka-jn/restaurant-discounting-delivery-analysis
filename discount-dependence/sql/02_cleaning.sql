-- ============================================================
-- Phase 2: Cleaning
--
-- Key decisions:
--   * Rating: raw sentinel is "0" for a new/unrated restaurant.
--     0 is not a rating of zero -- it's the absence of one.
--     Every "0" becomes NULL so it never pollutes an AVG().
--   * Number_of_Ratings arrives as text ("500+ ratings",
--     "1K+ ratings", "4 ratings"). Parsed to a numeric floor,
--     with a flag marking it as a floor (the "+" cases) vs an
--     exact count.
--   * Cost_for_two is already plain digits here, but stripped
--     defensively in case of stray currency symbols.
--   * Dedupe on the natural key (name, area, city, cuisine):
--     this dataset carries ~1,300 verbatim duplicate listings.
-- ============================================================

CREATE OR REPLACE TABLE clean_restaurants AS
WITH deduped AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY Restaurant_Name, Area, Location, Cuisine
            ORDER BY Restaurant_Name
        ) AS rn
    FROM stg_restaurants
),
base AS (
    SELECT
        TRIM(Restaurant_Name)                                  AS restaurant_name,
        NULLIF(TRIM(Cuisine), '')                               AS cuisine_raw,
        CASE
            WHEN Rating IS NULL OR TRIM(Rating) = '' THEN NULL
            WHEN TRY_CAST(Rating AS DOUBLE) = 0 THEN NULL
            ELSE TRY_CAST(Rating AS DOUBLE)
        END                                                      AS rating,
        Number_of_Ratings                                       AS rating_count_raw,
        CASE
            WHEN Number_of_Ratings IS NULL THEN NULL
            ELSE TRY_CAST(regexp_extract(Number_of_Ratings, '([0-9.]+)', 1) AS DOUBLE)
                 * CASE WHEN Number_of_Ratings ILIKE '%K%' THEN 1000 ELSE 1 END
        END                                                      AS rating_count,
        (Number_of_Ratings ILIKE '%+%')                          AS rating_count_is_floor,
        TRY_CAST(regexp_replace(Cost_for_two, '[^0-9]', '', 'g') AS INTEGER) AS cost_for_two,
        TRY_CAST(Number_of_Offers AS INTEGER)                    AS number_of_offers,
        NULLIF(Offer_Name, '')                                   AS offer_name_raw,
        NULLIF(TRIM(Area), '')                                   AS area,
        TRY_CAST(Pure_Veg AS BOOLEAN)                            AS pure_veg,
        TRIM(Location)                                           AS city
    FROM deduped
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY city, restaurant_name) AS restaurant_id,
    *
FROM base
WHERE restaurant_name IS NOT NULL
  AND cost_for_two IS NOT NULL
  AND cost_for_two > 0;

-- Cuisine bridge table: a multi-cuisine restaurant is counted
-- once per cuisine it lists, not just its first one.
CREATE OR REPLACE TABLE restaurant_cuisine AS
SELECT
    restaurant_id,
    TRIM(cuisine) AS cuisine,
    ROW_NUMBER() OVER (PARTITION BY restaurant_id ORDER BY ordinality) = 1 AS is_primary
FROM clean_restaurants,
     LATERAL UNNEST(str_split(cuisine_raw, ',')) WITH ORDINALITY AS t(cuisine, ordinality)
WHERE cuisine_raw IS NOT NULL AND TRIM(cuisine) != '';

SELECT COUNT(*) AS clean_row_count FROM clean_restaurants;
