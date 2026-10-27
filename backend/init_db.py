"""Create tables, views, triggers, functions and load sample data.  Usage: python init_db.py"""
import os
from pathlib import Path
import psycopg2

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:sanchit@localhost:5432/turf_db")
DB_DIR = Path(__file__).resolve().parent.parent / "database"

conn = psycopg2.connect(DATABASE_URL)
with conn, conn.cursor() as cur:
    for name in ("schema.sql", "seed.sql"):
        cur.execute((DB_DIR / name).read_text(encoding="utf-8"))
        print(f"Executed {name}")
conn.close()
print("Database ready.")
