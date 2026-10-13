-- ============================================================
-- Phase 2 (continued): Offer parsing -- the centrepiece.
--
-- Offer_Name is free text, multiple offers concatenated with
-- ", ", each offer itself 2-3 lines joined with \n:
--   [optional badge]      e.g. "FLAT DEAL", "TOP OFFER", "LATE NIGHT"
--   <discount clause>     e.g. "FLAT ₹120 OFF", "20% OFF UPTO ₹100",
--                              "BUY 1 GET 1 FREE"
--   <code / min-order>    e.g. "USE AXIS120ABOVE ₹500",
--                              "NO  REQUIREDABOVE ₹550"
-- The discount clause is always second-to-last line; the
-- code/min-order clause is always last. This structure was
-- reverse-engineered by inspecting ~150 raw samples before
-- writing a single regex.
-- ============================================================

CREATE OR REPLACE TABLE offers AS
WITH blocks AS (
    SELECT
        restaurant_id,
        ordinality AS offer_seq,
        TRIM(block) AS block
    FROM clean_restaurants,
         LATERAL UNNEST(str_split(offer_name_raw, ', ')) WITH ORDINALITY AS t(block, ordinality)
    WHERE offer_name_raw IS NOT NULL
),
parsed AS (
    SELECT
        restaurant_id,
        offer_seq,
        block AS raw_offer_text,
        str_split(block, chr(10)) AS lines
    FROM blocks
),
lined AS (
    SELECT
        restaurant_id,
        offer_seq,
        raw_offer_text,
        CASE WHEN len(lines) = 3 THEN lines[1] ELSE NULL END AS badge,
        lines[len(lines) - 1] AS discount_line,
        lines[len(lines)]     AS code_line
    FROM parsed
)
SELECT
    restaurant_id,
    offer_seq,
    raw_offer_text,
    badge,
    CASE
        WHEN discount_line ~ 'BUY [0-9]+ GET [0-9]+ FREE' THEN 'bogo'
        WHEN discount_line ~ '[0-9]+%'                    THEN 'percent_off'
        WHEN discount_line ~ 'FLAT ₹[0-9]+ OFF'            THEN 'flat_off'
        ELSE 'other'
    END AS offer_type,
    TRY_CAST(regexp_extract(discount_line, '([0-9]+)%', 1) AS INTEGER)        AS discount_pct,
    TRY_CAST(regexp_extract(discount_line, 'FLAT ₹([0-9]+) OFF', 1) AS INTEGER) AS flat_amount,
    TRY_CAST(regexp_extract(discount_line, 'UPTO ₹([0-9]+)', 1) AS INTEGER)     AS cap_amount,
    TRY_CAST(regexp_extract(code_line, 'ABOVE ₹([0-9]+)', 1) AS INTEGER)        AS min_order_amount,
    NULLIF(regexp_extract(code_line, 'USE ([A-Z0-9]+)', 1), '')                 AS promo_code
FROM lined;

-- Per-restaurant discount summary. "Depth" needs a single number
-- per restaurant to bin into bands. Percent-off offers give that
-- directly; flat-off offers don't carry a % at all, so we imply
-- one as flat_amount / cost_for_two -- flat rupees off relative
-- to what an order there actually costs. This is a stated
-- modelling assumption, not a measured percentage.
CREATE OR REPLACE TABLE restaurant_offer_summary AS
SELECT
    r.restaurant_id,
    COUNT(o.offer_seq) AS offer_count,
    MAX(o.offer_type = 'bogo') AS has_bogo,
    MAX(
        COALESCE(
            o.discount_pct,
            LEAST(100.0, o.flat_amount * 100.0 / NULLIF(r.cost_for_two, 0))
        )
    ) AS max_implied_discount_pct,
    MIN(o.min_order_amount) AS min_offer_threshold
FROM clean_restaurants r
LEFT JOIN offers o USING (restaurant_id)
GROUP BY r.restaurant_id;
