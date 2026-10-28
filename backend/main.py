"""TurfZone - Online Turf Booking System (FastAPI + PostgreSQL, raw SQL on purpose)."""
import os
import re
from contextlib import contextmanager
from pathlib import Path
from typing import List, Optional

import psycopg2
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from pydantic import BaseModel, Field

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:sanchit@localhost:5432/turf_db")
ROOT = Path(__file__).resolve().parent.parent
pool = SimpleConnectionPool(1, 10, DATABASE_URL)

app = FastAPI(title="TurfZone API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


# ------------------------------------------------------------------ DB helpers
def to_http(e: psycopg2.Error) -> HTTPException:
    """Translate PostgreSQL errors into clean HTTP errors."""
    msg = (e.diag.message_primary if e.diag and e.diag.message_primary else str(e)).strip()
    code = e.pgcode or ""
    if code == "P0001":                       # RAISE EXCEPTION from triggers / functions
        return HTTPException(409, msg)
    if code == "23505":                       # unique violation
        return HTTPException(409, "Already exists (duplicate value)")
    if code in ("23503", "23514", "23502", "22P02", "22007", "22008"):
        return HTTPException(400, msg)        # FK / CHECK / NOT NULL / bad input
    return HTTPException(500, msg)


@contextmanager
def db():
    """One transaction per request: commit on success, rollback on any error."""
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            yield cur
        conn.commit()
    except psycopg2.Error as e:
        conn.rollback()
        raise to_http(e)
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def query(sql, params=None):
    with db() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def query_one(sql, params=None):
    with db() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


# ------------------------------------------------------------------ Schemas
class UserIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=100)
    email: str = Field(pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    phone: str = Field(pattern=r"^[0-9]{10}$")
    role: str = "customer"


class TurfIn(BaseModel):
    name: str = Field(min_length=2)
    city: str
    area: str
    price_per_hour: float = Field(gt=0)
    capacity: int = Field(gt=0)
    description: Optional[str] = None
    is_active: bool = True
    sport_ids: List[int] = []


class BookingIn(BaseModel):
    user_id: int
    turf_id: int
    sport_id: int
    date: str
    start: str                      # "HH:MM"
    hours: int = Field(ge=1, le=4)
    method: str = "UPI"


class RescheduleIn(BaseModel):
    date: str
    start: str


class ReviewIn(BaseModel):
    user_id: int
    turf_id: int
    rating: int = Field(ge=1, le=5)
    comment: Optional[str] = None


# ------------------------------------------------------------------ Lookups
@app.get("/api/sports")
def list_sports():
    return query("SELECT sport_id, sport_name FROM sports ORDER BY sport_name")


@app.get("/api/cities")
def list_cities():
    return query("SELECT DISTINCT city FROM turfs WHERE is_active ORDER BY city")


@app.get("/api/dashboard")
def dashboard():
    return query_one("""
        SELECT (SELECT COUNT(*) FROM turfs WHERE is_active)               AS turfs,
               (SELECT COUNT(*) FROM users WHERE role = 'customer')       AS customers,
               (SELECT COUNT(*) FROM bookings WHERE status = 'CONFIRMED') AS upcoming,
               (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'PAID') AS revenue""")


# ------------------------------------------------------------------ Users (CRUD)
@app.get("/api/users")
def list_users():
    return query("""
        SELECT u.user_id, u.full_name, u.email, u.phone, u.role, u.created_at,
               (SELECT COUNT(*) FROM bookings b WHERE b.user_id = u.user_id) AS bookings
        FROM users u ORDER BY u.role, u.full_name""")


@app.post("/api/users", status_code=201)
def create_user(u: UserIn):
    if u.role not in ("customer", "admin"):
        raise HTTPException(400, "Invalid role")
    return query_one("""INSERT INTO users(full_name, email, phone, role)
                        VALUES (%(full_name)s, LOWER(%(email)s), %(phone)s, %(role)s) RETURNING *""", u.model_dump())


@app.put("/api/users/{user_id}")
def update_user(user_id: int, u: UserIn):
    row = query_one("""UPDATE users SET full_name=%(full_name)s, email=LOWER(%(email)s), phone=%(phone)s, role=%(role)s
                       WHERE user_id=%(id)s RETURNING *""", {**u.model_dump(), "id": user_id})
    if not row:
        raise HTTPException(404, "User not found")
    return row


@app.delete("/api/users/{user_id}")
def delete_user(user_id: int):
    if not query_one("DELETE FROM users WHERE user_id=%s RETURNING user_id", (user_id,)):
        raise HTTPException(404, "User not found")
    return {"message": "User deleted (their bookings and reviews were removed by ON DELETE CASCADE)"}


# ------------------------------------------------------------------ Turfs (CRUD)
SORTS = {
    "price_asc": "t.price_per_hour ASC", "price_desc": "t.price_per_hour DESC",
    "rating": "s.avg_rating DESC, s.review_count DESC", "popular": "s.total_bookings DESC", "name": "t.name ASC",
}


@app.get("/api/turfs")
def list_turfs(q: Optional[str] = None, city: Optional[str] = None, sport: Optional[str] = None,
               max_price: Optional[float] = None, sort: str = "popular", include_inactive: bool = False):
    sql = f"""
        SELECT t.*, s.total_bookings, s.revenue, s.avg_rating, s.review_count,
               COALESCE((SELECT JSON_AGG(JSON_BUILD_OBJECT('id', sp.sport_id, 'name', sp.sport_name) ORDER BY sp.sport_name)
                         FROM turf_sports ts JOIN sports sp ON sp.sport_id = ts.sport_id
                         WHERE ts.turf_id = t.turf_id), '[]'::json) AS sport_list
        FROM turfs t JOIN v_turf_stats s ON s.turf_id = t.turf_id
        WHERE (t.is_active OR %(inactive)s)
          AND (%(q)s IS NULL OR t.name ILIKE '%%' || %(q)s || '%%' OR t.area ILIKE '%%' || %(q)s || '%%')
          AND (%(city)s IS NULL OR t.city = %(city)s)
          AND (%(max_price)s IS NULL OR t.price_per_hour <= %(max_price)s)
          AND (%(sport)s IS NULL OR EXISTS (SELECT 1 FROM turf_sports ts JOIN sports sp ON sp.sport_id = ts.sport_id
                                            WHERE ts.turf_id = t.turf_id AND sp.sport_name = %(sport)s))
        ORDER BY {SORTS.get(sort, SORTS['popular'])}"""
    return query(sql, {"q": q or None, "city": city or None, "sport": sport or None,
                       "max_price": max_price, "inactive": include_inactive})


@app.post("/api/turfs", status_code=201)
def create_turf(t: TurfIn):
    with db() as cur:                                # two statements, one transaction
        cur.execute("""INSERT INTO turfs(name, city, area, price_per_hour, capacity, description, is_active)
                       VALUES (%(name)s, %(city)s, %(area)s, %(price_per_hour)s, %(capacity)s, %(description)s, %(is_active)s)
                       RETURNING turf_id""", t.model_dump())
        turf_id = cur.fetchone()["turf_id"]
        cur.execute("INSERT INTO turf_sports(turf_id, sport_id) SELECT %s, UNNEST(%s::int[])", (turf_id, t.sport_ids))
    return {"turf_id": turf_id}


@app.put("/api/turfs/{turf_id}")
def update_turf(turf_id: int, t: TurfIn):
    with db() as cur:
        cur.execute("""UPDATE turfs SET name=%(name)s, city=%(city)s, area=%(area)s, price_per_hour=%(price_per_hour)s,
                       capacity=%(capacity)s, description=%(description)s, is_active=%(is_active)s
                       WHERE turf_id=%(id)s RETURNING turf_id""", {**t.model_dump(), "id": turf_id})
        if not cur.fetchone():
            raise HTTPException(404, "Turf not found")
        cur.execute("DELETE FROM turf_sports WHERE turf_id=%s", (turf_id,))
        cur.execute("INSERT INTO turf_sports(turf_id, sport_id) SELECT %s, UNNEST(%s::int[])", (turf_id, t.sport_ids))
    return {"message": "Turf updated"}


@app.patch("/api/turfs/{turf_id}/toggle")
def toggle_turf(turf_id: int):
    row = query_one("UPDATE turfs SET is_active = NOT is_active WHERE turf_id=%s RETURNING is_active", (turf_id,))
    if not row:
        raise HTTPException(404, "Turf not found")
    return row


@app.delete("/api/turfs/{turf_id}")
def delete_turf(turf_id: int):
    if not query_one("DELETE FROM turfs WHERE turf_id=%s RETURNING turf_id", (turf_id,)):
        raise HTTPException(404, "Turf not found")
    return {"message": "Turf deleted"}


@app.get("/api/turfs/{turf_id}/slots")
def turf_slots(turf_id: int, date: str):
    """Availability grid: generate_series for hours + NOT EXISTS against bookings."""
    return query("""
        SELECT h AS hour, TO_CHAR(make_time(h, 0, 0), 'HH24:MI') AS label,
               (NOT EXISTS (SELECT 1 FROM bookings b
                            WHERE b.turf_id = %(t)s AND b.booking_date = %(d)s::date AND b.status <> 'CANCELLED'
                              AND make_time(h, 0, 0) >= b.start_time AND make_time(h, 0, 0) < b.end_time)
                AND NOT (%(d)s::date = CURRENT_DATE AND h <= EXTRACT(HOUR FROM LOCALTIME))) AS available
        FROM generate_series(6, 22) AS h ORDER BY h""", {"t": turf_id, "d": date})


@app.get("/api/turfs/{turf_id}/reviews")
def turf_reviews(turf_id: int):
    return query("""SELECT r.review_id, u.full_name, r.rating, r.comment, r.created_at
                    FROM reviews r JOIN users u ON u.user_id = r.user_id
                    WHERE r.turf_id = %s ORDER BY r.created_at DESC""", (turf_id,))


# ------------------------------------------------------------------ Bookings
@app.get("/api/bookings")
def list_bookings(user_id: Optional[int] = None):
    return query("""SELECT * FROM v_booking_details
                    WHERE (%(u)s IS NULL OR user_id = %(u)s)
                    ORDER BY booking_date DESC, start_time DESC""", {"u": user_id})


@app.post("/api/bookings", status_code=201)
def create_booking(b: BookingIn):
    if b.method not in ("UPI", "CARD", "CASH"):
        raise HTTPException(400, "Invalid payment method")
    row = query_one("""SELECT fn_book_turf(%(user_id)s, %(turf_id)s, %(sport_id)s, %(date)s::date,
                                           %(start)s::time, %(hours)s, %(method)s) AS booking_id""", b.model_dump())
    return row


@app.put("/api/bookings/{booking_id}/reschedule")
def reschedule(booking_id: int, r: RescheduleIn):
    row = query_one("""UPDATE bookings
                       SET booking_date = %(d)s::date,
                           end_time     = %(s)s::time + (end_time - start_time),
                           start_time   = %(s)s::time
                       WHERE booking_id = %(id)s AND status = 'CONFIRMED' AND %(d)s::date >= CURRENT_DATE
                       RETURNING booking_id""", {"d": r.date, "s": r.start, "id": booking_id})
    if not row:
        raise HTTPException(400, "Only upcoming confirmed bookings can be rescheduled")
    return {"message": "Booking rescheduled"}


@app.put("/api/bookings/{booking_id}/cancel")
def cancel_booking(booking_id: int):
    return query_one("SELECT fn_cancel_booking(%s) AS message", (booking_id,))


@app.delete("/api/bookings/{booking_id}")
def delete_booking(booking_id: int):
    if not query_one("DELETE FROM bookings WHERE booking_id=%s RETURNING booking_id", (booking_id,)):
        raise HTTPException(404, "Booking not found")
    return {"message": "Booking deleted"}


# ------------------------------------------------------------------ Reviews (UPSERT)
@app.post("/api/reviews", status_code=201)
def add_review(r: ReviewIn):
    row = query_one("""
        INSERT INTO reviews(user_id, turf_id, rating, comment)
        SELECT %(user_id)s, %(turf_id)s, %(rating)s, %(comment)s
        WHERE EXISTS (SELECT 1 FROM bookings WHERE user_id = %(user_id)s AND turf_id = %(turf_id)s AND status = 'COMPLETED')
        ON CONFLICT (user_id, turf_id) DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, created_at = NOW()
        RETURNING review_id""", r.model_dump())
    if not row:
        raise HTTPException(400, "You can review a turf only after a completed booking")
    return {"message": "Thanks for your review!"}


# ------------------------------------------------------------------ DB Lab
def load_lab():
    text = (ROOT / "database" / "queries.sql").read_text(encoding="utf-8")
    items = []
    for block in re.split(r"^-- @key:", text, flags=re.M)[1:]:
        head, _, rest = block.partition("\n")
        meta, body = {"key": head.strip()}, []
        for line in rest.split("\n"):
            m = re.match(r"-- @(\w+):\s*(.*)", line)
            if m:
                meta[m.group(1)] = m.group(2).strip()
            else:
                body.append(line)
        meta["sql"] = "\n".join(body).strip()
        items.append(meta)
    return items


@app.get("/api/lab")
def lab_list():
    return load_lab()


@app.get("/api/lab/{key}")
def lab_run(key: str):
    item = next((i for i in load_lab() if i["key"] == key), None)   # only whitelisted queries run
    if not item:
        raise HTTPException(404, "Unknown query")
    with db() as cur:
        cur.execute("SET TRANSACTION READ ONLY")
        cur.execute(item["sql"])
        rows = cur.fetchall() if cur.description else [{"status": "Success", "message": "Query executed successfully"}]
    return {**item, "rows": rows}


# ------------------------------------------------------------------ Frontend (served last)
app.mount("/", StaticFiles(directory=ROOT / "frontend", html=True), name="frontend")
