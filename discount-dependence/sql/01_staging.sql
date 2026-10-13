-- ============================================================
-- Phase 1: Staging
-- Load raw CSV as-is, every column VARCHAR. Nothing casts on
-- load: forcing types here would silently drop rows on any
-- malformed value, and we'd never see it happen.
-- Source: Kaggle "Swiggy Restaurants" (anjan46/swiggy-personal),
-- 140,657 restaurant listings scraped across 581 Indian cities.
-- ============================================================

CREATE OR REPLACE TABLE stg_restaurants AS
SELECT *
FROM read_csv_auto(
    'data/raw/swiggy_restaurants.csv',
    ALL_VARCHAR = TRUE,
    HEADER = TRUE
);

-- Reconciliation checkpoint: row count in vs row count out.
SELECT COUNT(*) AS staged_row_count FROM stg_restaurants;
