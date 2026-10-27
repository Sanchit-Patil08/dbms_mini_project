-- =====================================================================
--  DDL / DML / TCL / DCL demo. Run in psql:  \i database/dml_ddl_demo.sql
-- =====================================================================
BEGIN;                                              -- TCL: start transaction

-- DDL
ALTER TABLE turfs ADD COLUMN floodlights BOOLEAN DEFAULT TRUE;
ALTER TABLE turfs RENAME COLUMN floodlights TO has_floodlights;
CREATE INDEX idx_users_role ON users(role);
CREATE TEMP TABLE temp_promo (code TEXT PRIMARY KEY, discount INT CHECK (discount BETWEEN 1 AND 90));
TRUNCATE temp_promo;

-- DML: INSERT (multi-row, RETURNING)
INSERT INTO temp_promo VALUES ('WELCOME10', 10), ('WEEKEND20', 20);
INSERT INTO users(full_name, email, phone) VALUES ('Demo User', 'demo@mail.com', '9111111111') RETURNING user_id;

-- DML: UPDATE (with subquery and RETURNING)
UPDATE turfs SET price_per_hour = price_per_hour * 1.10
WHERE city = 'Mumbai' AND turf_id IN (SELECT turf_id FROM v_turf_stats WHERE avg_rating >= 4)
RETURNING name, price_per_hour;

-- DML: UPSERT
INSERT INTO reviews(user_id, turf_id, rating, comment) VALUES (2, 1, 3, 'Changed my mind')
ON CONFLICT (user_id, turf_id) DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment;

SAVEPOINT before_delete;                            -- TCL
DELETE FROM bookings WHERE status = 'CANCELLED' AND booking_date < CURRENT_DATE;   -- DML: DELETE
ROLLBACK TO SAVEPOINT before_delete;                -- undo only the delete

-- Stored function calls
SELECT fn_book_turf(3, 4, 1, CURRENT_DATE + 7, TIME '10:00', 2, 'UPI') AS new_booking_id;
SELECT fn_cancel_booking(currval('bookings_booking_id_seq')::INT);

-- DCL
CREATE ROLE turf_readonly NOLOGIN;
GRANT SELECT ON v_turf_stats, v_booking_details, turfs, sports TO turf_readonly;
REVOKE SELECT ON v_booking_details FROM turf_readonly;

ROLLBACK;                                           -- TCL: discard the whole demo
