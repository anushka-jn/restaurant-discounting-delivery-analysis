-- ============================================================
-- Phase 3: Derived dimensions
-- ============================================================

CREATE OR REPLACE TABLE restaurant_features AS
SELECT
    r.restaurant_id,
    r.restaurant_name,
    r.city,
    r.area,
    r.cost_for_two,
    r.rating,
    r.rating_count,
    r.rating_count_is_floor,
    r.pure_veg,
    pc.cuisine AS primary_cuisine,

    CASE
        WHEN r.cost_for_two < 200 THEN 'Budget'
        WHEN r.cost_for_two < 400 THEN 'Value'
        WHEN r.cost_for_two < 700 THEN 'Mid'
        ELSE 'Premium'
    END AS price_band,

    COALESCE(s.offer_count, 0) AS offer_count,
    (COALESCE(s.offer_count, 0) > 0) AS has_offer,
    s.has_bogo,
    s.max_implied_discount_pct AS discount_depth_pct,

    CASE
        WHEN COALESCE(s.offer_count, 0) = 0 OR s.max_implied_discount_pct IS NULL THEN 'None'
        WHEN s.max_implied_discount_pct < 15 THEN 'Low'
        WHEN s.max_implied_discount_pct < 30 THEN 'Mid'
        WHEN s.max_implied_discount_pct < 50 THEN 'High'
        ELSE 'Very High'
    END AS discount_depth_band,

    (COALESCE(r.rating_count, 0) < 20) AS cold_start_flag,

    r.city || ' || ' || COALESCE(pc.cuisine, 'Unknown') || ' || ' ||
        CASE
            WHEN r.cost_for_two < 200 THEN 'Budget'
            WHEN r.cost_for_two < 400 THEN 'Value'
            WHEN r.cost_for_two < 700 THEN 'Mid'
            ELSE 'Premium'
        END AS peer_group_key

FROM clean_restaurants r
LEFT JOIN restaurant_offer_summary s USING (restaurant_id)
LEFT JOIN restaurant_cuisine pc ON pc.restaurant_id = r.restaurant_id AND pc.is_primary;

-- Peer-group sizes, so thin cells can be dropped from
-- percentile-based comparisons rather than silently distorting them.
CREATE OR REPLACE TABLE peer_group_sizes AS
SELECT peer_group_key, COUNT(*) AS n
FROM restaurant_features
GROUP BY peer_group_key;

SELECT COUNT(*) FROM restaurant_features;
