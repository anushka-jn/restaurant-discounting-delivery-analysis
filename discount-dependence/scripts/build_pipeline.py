"""
Discount Dependence Analysis -- pipeline runner.

Executes sql/01..05 in order against DuckDB, then exports every
analysis table (a1..a12) plus headline summary numbers to
dashboard/data.json for the dashboard, and to data/processed/*.csv
for anyone who wants the raw tables.
"""
import json
import os
import duckdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

SQL_FILES = [
    "sql/01_staging.sql",
    "sql/02_cleaning.sql",
    "sql/03_offers.sql",
    "sql/04_features.sql",
    "sql/05_analysis.sql",
]

ANALYSIS_TABLES = [
    "a1_penetration_city", "a2_penetration_cuisine", "a3_depth_by_price_band",
    "a4_demand_response", "a5_saturation", "a6_rating_quality_vs_depth",
    "a9_leakage_overall", "a9_leakage_by_price_band",
    "a10_cold_start_check", "a11_offer_type_mix", "a12_recommendation",
]

def main():
    con = duckdb.connect("data/processed/warehouse.duckdb")

    for path in SQL_FILES:
        print(f"--- running {path} ---")
        sql = open(path).read()
        result = con.execute(sql)
        try:
            row = result.fetchone()
            if row is not None:
                print("   ->", row)
        except Exception:
            pass

    os.makedirs("data/processed", exist_ok=True)
    output = {}

    for t in ANALYSIS_TABLES:
        df = con.execute(f"SELECT * FROM {t}").df()
        df.to_csv(f"data/processed/{t}.csv", index=False)
        output[t] = json.loads(df.to_json(orient="records"))
        print(f"{t}: {len(df)} rows")

    # Headline numbers for the dashboard's summary cards.
    total_restaurants = con.execute("SELECT COUNT(*) FROM restaurant_features").fetchone()[0]
    total_cities = con.execute("SELECT COUNT(DISTINCT city) FROM restaurant_features").fetchone()[0]
    pct_with_offer = con.execute(
        "SELECT ROUND(100.0*SUM(has_offer::INT)/COUNT(*),1) FROM restaurant_features"
    ).fetchone()[0]
    scored_n = con.execute("SELECT COUNT(*) FROM a8_quadrants").fetchone()[0]
    over_discounter_pct = con.execute(
        "SELECT ROUND(100.0*SUM((quadrant='Over-Discounter')::INT)/COUNT(*),1) FROM a8_quadrants"
    ).fetchone()[0]
    organic_star_pct = con.execute(
        "SELECT ROUND(100.0*SUM((quadrant='Organic Star')::INT)/COUNT(*),1) FROM a8_quadrants"
    ).fetchone()[0]
    n_dropped_thin = con.execute(
        "SELECT COUNT(*) FROM restaurant_features f LEFT JOIN peer_group_sizes pg USING(peer_group_key) WHERE pg.n < 15"
    ).fetchone()[0]
    cuisine_count = con.execute("SELECT COUNT(DISTINCT primary_cuisine) FROM restaurant_features").fetchone()[0]

    output["summary"] = {
        "total_restaurants": total_restaurants,
        "total_cities": total_cities,
        "total_cuisines": cuisine_count,
        "pct_with_offer": pct_with_offer,
        "scored_n": scored_n,
        "n_dropped_thin_peer_groups": n_dropped_thin,
        "over_discounter_pct": over_discounter_pct,
        "organic_star_pct": organic_star_pct,
    }

    # Export cleaned + feature tables for portfolio / reruns.
    con.execute("COPY restaurant_features TO 'data/processed/restaurant_features.parquet' (FORMAT PARQUET)")
    con.execute("COPY offers TO 'data/processed/offers.parquet' (FORMAT PARQUET)")

    with open("dashboard/data.json", "w") as f:
        json.dump(output, f, indent=2)

    print("\n=== SUMMARY ===")
    print(json.dumps(output["summary"], indent=2))
    print("\nWrote dashboard/data.json")

    con.close()

if __name__ == "__main__":
    main()
