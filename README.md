# 🏟️ TurfZone - Online Turf Booking System (DBMS Mini Project)

PostgreSQL + FastAPI (raw SQL, no ORM) + Vanilla JS + Bootstrap 5.

## Run it
```bash
createdb turf_db                       # or create it in pgAdmin
cd backend
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/turf_db   # Windows: set DATABASE_URL=...
python init_db.py                      # runs database/schema.sql + seed.sql
uvicorn main:app --reload
```
Open http://127.0.0.1:8000 (API docs: /docs). Use the user dropdown in the navbar to switch between
customers and the **Admin Manager**. Re-run `python init_db.py` any time to reset the demo data.

## Project layout
| Path | Purpose |
|---|---|
| `database/schema.sql` | Tables, constraints, indexes, views, triggers, stored functions |
| `database/seed.sql` | Sample data (INSERT, INSERT...SELECT) |
| `database/queries.sql` | 29 SELECT demos, executed live by the **DB Lab** page |
| `database/dml_ddl_demo.sql` | ALTER/TRUNCATE, UPDATE, DELETE, UPSERT, SAVEPOINT, GRANT/REVOKE (rolled back at end) |
| `backend/main.py` | FastAPI endpoints (every endpoint = hand-written SQL) |
| `frontend/` | `index.html`, `style.css`, `app.js` |

## ER design (3NF)
users 1─∞ bookings ∞─1 turfs · bookings 1─1 payments · users ∞─∞ turfs via reviews · turfs ∞─∞ sports via turf_sports · booking_audit (trigger-filled log)

## DBMS concepts checklist
| Concept | Where |
|---|---|
| **DQL (Data Query Language)** | `database/queries.sql` (WHERE, BETWEEN, IN, LIKE/ILIKE, ORDER BY, LIMIT, DISTINCT, CASE, COALESCE) |
| **Aggregate Functions: GROUP BY & HAVING** | `database/queries.sql` (COUNT, SUM, AVG, MIN, MAX, STRING_AGG, multi-column GROUP BY, HAVING thresholds) |
| **Views in SQL** | `database/schema.sql`, `database/queries.sql` (`v_booking_details`, `v_turf_stats`, `v_customer_summary`, `v_daily_revenue`) |
| **Joins** | `database/queries.sql` (INNER, LEFT OUTER, RIGHT OUTER, FULL OUTER, SELF, CROSS) |
| **Data Control Commands (DCL)** | `database/schema.sql`, `database/dml_ddl_demo.sql`, `database/queries.sql` (CREATE ROLE, GRANT, REVOKE, `information_schema.table_privileges`, `pg_roles`) |
| **Triggers** | `database/schema.sql`, `database/queries.sql` (`trg_booking_overlap` BEFORE, `trg_booking_audit` AFTER, `trg_review_validation`, `booking_audit` log) |
| **PL/SQL (PL/pgSQL Functions & Procedures)** | `database/schema.sql`, `database/queries.sql` (`fn_book_turf`, `fn_cancel_booking`, `fn_calculate_turf_revenue`, `fn_check_slot_available`, `fn_get_customer_stats`) |
| **Transaction from SQL (TCL)** | `database/schema.sql`, `database/dml_ddl_demo.sql`, `database/queries.sql` (BEGIN/COMMIT/ROLLBACK, SAVEPOINT, row locking `FOR UPDATE`, `txid_current()`, `pg_locks`) |
| DDL: CREATE/ALTER/DROP/TRUNCATE | `schema.sql`, `dml_ddl_demo.sql` |
| Constraints: PK, FK (CASCADE / SET NULL), UNIQUE, CHECK, NOT NULL, DEFAULT, composite PK | `schema.sql` |
| DML: INSERT, INSERT...SELECT, UPDATE, DELETE, RETURNING, UPSERT (ON CONFLICT) | `seed.sql`, `main.py`, `dml_ddl_demo.sql` |
| Subqueries: scalar, IN, EXISTS/NOT EXISTS, correlated, ALL/ANY | `queries.sql` |
| Set ops: UNION, INTERSECT, EXCEPT | `queries.sql` |
| CTE & Window Functions: RANK, ROW_NUMBER, running SUM, percentage of total | `queries.sql` |
| Query Execution Plan: EXPLAIN | `queries.sql` |

## Booking rules (enforced in the database, not in Python)
Open 06:00-23:00 · 1-4 hour bookings · no past or already-started slots · weekend rate +20% ·
no overlapping bookings (trigger) · cancel = status change + payment REFUNDED · review allowed only after a COMPLETED booking.
