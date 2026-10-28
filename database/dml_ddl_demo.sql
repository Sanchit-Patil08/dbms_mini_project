-- =====================================================================
--  DDL / DML / TCL / DCL / Triggers / PLSQL / Views Demo
--  Run in psql:  \i database/dml_ddl_demo.sql
--  Everything is rolled back at the end, so your data stays untouched.
-- =====================================================================
BEGIN;                                              -- TCL: start transaction

-- 1. DDL: ALTER, RENAME, CREATE INDEX, TEMP TABLE, TRUNCATE
ALTER TABLE turfs ADD COLUMN floodlights BOOLEAN DEFAULT TRUE;
ALTER TABLE turfs RENAME COLUMN floodlights TO has_floodlights;
CREATE INDEX idx_users_role ON users(role);
CREATE TEMP TABLE temp_promo (code TEXT PRIMARY KEY, discount INT CHECK (discount BETWEEN 1 AND 90));
TRUNCATE temp_promo;

-- 2. DML: INSERT (multi-row, RETURNING)
INSERT INTO temp_promo VALUES ('WELCOME10', 10), ('WEEKEND20', 20);
INSERT INTO users(full_name, email, phone) VALUES ('Demo User', 'demo@mail.com', '9111111111') RETURNING user_id;

-- 3. DML: UPDATE (with subquery and RETURNING)
UPDATE turfs SET price_per_hour = price_per_hour * 1.10
WHERE city = 'Mumbai' AND turf_id IN (SELECT turf_id FROM v_turf_stats WHERE avg_rating >= 4)
RETURNING name, price_per_hour;

-- 4. DML: UPSERT (ON CONFLICT DO UPDATE)
INSERT INTO reviews(user_id, turf_id, rating, comment) VALUES (2, 1, 3, 'Changed my mind')
ON CONFLICT (user_id, turf_id) DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment;

-- 5. TCL: SAVEPOINT and Selective ROLLBACK
SAVEPOINT before_delete;                            -- TCL SAVEPOINT
DELETE FROM bookings WHERE status = 'CANCELLED' AND booking_date < CURRENT_DATE;   -- DML: DELETE
ROLLBACK TO SAVEPOINT before_delete;                -- TCL ROLLBACK TO SAVEPOINT (reverts delete only)

-- 6. VIEWS Querying
SELECT * FROM v_booking_details LIMIT 3;
SELECT * FROM v_turf_stats WHERE total_bookings > 0;
SELECT * FROM v_customer_summary WHERE total_bookings > 0;
SELECT * FROM v_daily_revenue LIMIT 5;

-- 7. PL/SQL Stored Functions & Procedures
SELECT fn_book_turf(3, 4, 1, CURRENT_DATE + 7, TIME '10:00', 2, 'UPI') AS new_booking_id;
SELECT fn_calculate_turf_revenue(4) AS turf_4_revenue;
SELECT fn_check_slot_available(4, CURRENT_DATE + 7, TIME '10:00', TIME '12:00') AS is_available;
SELECT * FROM fn_get_customer_stats(3);
SELECT fn_cancel_booking(currval('bookings_booking_id_seq')::INT);

-- 8. TRIGGERS Verification
-- The status cancellation above triggers trg_booking_audit, writing to booking_audit:
SELECT audit_id, booking_id, old_status, new_status, changed_at FROM booking_audit ORDER BY audit_id DESC LIMIT 2;

-- 9. DCL: Data Control Commands
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'turf_readonly') THEN
        CREATE ROLE turf_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'turf_manager') THEN
        CREATE ROLE turf_manager NOLOGIN;
    END IF;
END $$;
GRANT SELECT ON v_turf_stats, v_booking_details, v_customer_summary, turfs, sports TO turf_readonly;
GRANT SELECT, INSERT, UPDATE ON bookings, payments, reviews TO turf_manager;
REVOKE SELECT ON v_booking_details FROM turf_readonly;
REVOKE DELETE ON bookings, payments FROM turf_manager;

-- 10. TCL: Final Rollback (keeps database clean)
ROLLBACK;                                           -- TCL: discard all changes
