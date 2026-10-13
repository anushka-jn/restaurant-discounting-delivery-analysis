-- ============================================================
-- Phase 1: Staging
-- Source: Kaggle "Zomato Delivery Operations Analytics Dataset"
-- (saurabhbadole), 45,584 real order-level delivery records.
-- Load everything as VARCHAR first -- several numeric columns
-- carry a literal "NaN" string, which a typed read would turn
-- into a silent parse failure instead of a visible null.
-- ============================================================

CREATE OR REPLACE TABLE stg_deliveries AS
SELECT *
FROM read_csv_auto(
    'data/raw/zomato_delivery.csv',
    ALL_VARCHAR = TRUE,
    HEADER = TRUE
);

SELECT COUNT(*) AS staged_row_count FROM stg_deliveries;
