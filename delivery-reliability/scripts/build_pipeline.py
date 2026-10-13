"""Delivery Performance Dashboard -- pipeline runner."""
import json
import os
import duckdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

SQL_FILES = [
    "sql/01_staging.sql",
    "sql/02_cleaning.sql",
    "sql/03_features.sql",
    "sql/04_analysis.sql",
]

ANALYSIS_TABLES = [
    "b1_overview", "b1_by_date", "b1_distance_dist",
    "b2_heatmap",
    "b3_rider_rating", "b3_vehicle", "b3_vehicle_condition", "b3_multiple_deliveries",
    "b4_order_type_traffic", "b4_delay_decomposition",
    "b5_breach_drivers",
]

def main():
    con = duckdb.connect("data/processed/warehouse.duckdb")
    for path in SQL_FILES:
        print(f"--- running {path} ---")
        row = con.execute(open(path).read()).fetchone()
        if row is not None:
            print("   ->", row)

    os.makedirs("data/processed", exist_ok=True)
    output = {}
    for t in ANALYSIS_TABLES:
        df = con.execute(f"SELECT * FROM {t}").df()
        # DuckDB DATE columns come back as python date objects; pandas'
        # to_json silently serializes those as epoch seconds instead of
        # ISO strings, which breaks any JS expecting a date string.
        for col in df.columns:
            if df[col].dtype == "object" and len(df) and hasattr(df[col].iloc[0], "isoformat"):
                df[col] = df[col].astype(str)
        df.to_csv(f"data/processed/{t}.csv", index=False)
        output[t] = json.loads(df.to_json(orient="records"))
        print(f"{t}: {len(df)} rows")

    n_total = con.execute("SELECT COUNT(*) FROM delivery_features").fetchone()[0]
    n_cities = con.execute("SELECT COUNT(DISTINCT rider_city) FROM delivery_features").fetchone()[0]
    n_dropped_bad_distance = con.execute(
        "SELECT COUNT(*) FROM delivery_features WHERE NOT valid_distance"
    ).fetchone()[0]

    output["summary"] = output["b1_overview"][0]
    output["summary"]["n_total"] = n_total
    output["summary"]["n_cities"] = n_cities
    output["summary"]["n_dropped_bad_distance"] = n_dropped_bad_distance

    con.execute("COPY delivery_features TO 'data/processed/delivery_features.parquet' (FORMAT PARQUET)")

    with open("dashboard/data.json", "w") as f:
        json.dump(output, f, indent=2, default=str)

    print("\n=== SUMMARY ===")
    print(json.dumps(output["summary"], indent=2, default=str))
    con.close()

if __name__ == "__main__":
    main()
