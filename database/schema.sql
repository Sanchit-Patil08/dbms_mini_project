-- =====================================================================
--  TurfZone  |  Online Turf Booking System  |  PostgreSQL schema
--  Covers: DDL, constraints, indexes, views, functions, triggers
-- =====================================================================
DROP TABLE IF EXISTS booking_audit, reviews, payments, bookings, turf_sports, turfs, sports, users CASCADE;

-- ---------- TABLES (DDL + integrity constraints) ----------
CREATE TABLE users (
    user_id     SERIAL PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(120) NOT NULL UNIQUE,
    phone       VARCHAR(10)  NOT NULL CHECK (phone ~ '^[0-9]{10}$'),
    role        VARCHAR(10)  NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','admin')),
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE sports (
    sport_id    SERIAL PRIMARY KEY,
    sport_name  VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE turfs (
    turf_id        SERIAL PRIMARY KEY,
    name           VARCHAR(100)  NOT NULL,
    city           VARCHAR(60)   NOT NULL,
    area           VARCHAR(80)   NOT NULL,
    price_per_hour NUMERIC(8,2)  NOT NULL CHECK (price_per_hour > 0),
    capacity       INT           NOT NULL CHECK (capacity > 0),
    is_active      BOOLEAN       NOT NULL DEFAULT TRUE,
    description    TEXT,
    created_at     TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- Many-to-many: a turf supports many sports, a sport is played on many turfs
CREATE TABLE turf_sports (
    turf_id   INT NOT NULL REFERENCES turfs(turf_id)   ON DELETE CASCADE,
    sport_id  INT NOT NULL REFERENCES sports(sport_id) ON DELETE CASCADE,
    PRIMARY KEY (turf_id, sport_id)
);

CREATE TABLE bookings (
    booking_id    SERIAL PRIMARY KEY,
    user_id       INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    turf_id       INT NOT NULL REFERENCES turfs(turf_id) ON DELETE CASCADE,
    sport_id      INT REFERENCES sports(sport_id) ON DELETE SET NULL,
    booking_date  DATE         NOT NULL,
    start_time    TIME         NOT NULL,
    end_time      TIME         NOT NULL,
    total_amount  NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),
    status        VARCHAR(12)  NOT NULL DEFAULT 'CONFIRMED'
                  CHECK (status IN ('CONFIRMED','CANCELLED','COMPLETED')),
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
    CHECK (end_time > start_time),
    CHECK (start_time >= TIME '06:00' AND end_time <= TIME '23:00')   -- turf opening hours
);

CREATE TABLE payments (
    payment_id  SERIAL PRIMARY KEY,
    booking_id  INT NOT NULL UNIQUE REFERENCES bookings(booking_id) ON DELETE CASCADE,  -- 1:1
    amount      NUMERIC(10,2) NOT NULL,
    method      VARCHAR(10) NOT NULL CHECK (method IN ('UPI','CARD','CASH')),
    status      VARCHAR(10) NOT NULL DEFAULT 'PAID' CHECK (status IN ('PAID','REFUNDED')),
    paid_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE reviews (
    review_id   SERIAL PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    turf_id     INT NOT NULL REFERENCES turfs(turf_id) ON DELETE CASCADE,
    rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, turf_id)                       -- one review per user per turf
);

-- Filled automatically by trigger (no FK on purpose: history survives deletes)
CREATE TABLE booking_audit (
    audit_id    SERIAL PRIMARY KEY,
    booking_id  INT NOT NULL,
    old_status  VARCHAR(12),
    new_status  VARCHAR(12),
    changed_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------- INDEXES ----------
CREATE INDEX idx_turfs_city          ON turfs(city);
CREATE INDEX idx_bookings_turf_date  ON bookings(turf_id, booking_date);   -- composite: availability lookups
CREATE INDEX idx_bookings_user       ON bookings(user_id);
CREATE INDEX idx_active_bookings     ON bookings(booking_date) WHERE status <> 'CANCELLED';  -- partial index
CREATE INDEX idx_reviews_turf        ON reviews(turf_id);

-- ---------- VIEWS ----------
CREATE VIEW v_booking_details AS
SELECT b.booking_id, b.user_id, u.full_name, u.email,
       b.turf_id, t.name AS turf_name, t.city, t.area,
       b.sport_id, s.sport_name,
       b.booking_date, b.start_time, b.end_time,
       b.total_amount, b.status,
       p.method AS payment_method, p.status AS payment_status
FROM bookings b
JOIN users u        ON u.user_id  = b.user_id
JOIN turfs t        ON t.turf_id  = b.turf_id
LEFT JOIN sports s  ON s.sport_id = b.sport_id
LEFT JOIN payments p ON p.booking_id = b.booking_id;

CREATE VIEW v_turf_stats AS
SELECT t.turf_id, t.name, t.city, t.price_per_hour,
       COALESCE(b.total_bookings, 0) AS total_bookings,
       COALESCE(b.revenue, 0)        AS revenue,
       COALESCE(r.avg_rating, 0)     AS avg_rating,
       COALESCE(r.review_count, 0)   AS review_count
FROM turfs t
LEFT JOIN (SELECT turf_id, COUNT(*) AS total_bookings, SUM(total_amount) AS revenue
           FROM bookings WHERE status <> 'CANCELLED' GROUP BY turf_id) b ON b.turf_id = t.turf_id
LEFT JOIN (SELECT turf_id, ROUND(AVG(rating),1) AS avg_rating, COUNT(*) AS review_count
           FROM reviews GROUP BY turf_id) r ON r.turf_id = t.turf_id;

-- Additional View: Customer Summary with aggregations
CREATE OR REPLACE VIEW v_customer_summary AS
SELECT 
    u.user_id,
    u.full_name,
    u.email,
    u.phone,
    COUNT(b.booking_id) AS total_bookings,
    COUNT(CASE WHEN b.status = 'COMPLETED' THEN 1 END) AS completed_bookings,
    COALESCE(SUM(CASE WHEN b.status <> 'CANCELLED' THEN b.total_amount ELSE 0 END), 0.00) AS total_spent,
    COUNT(DISTINCT r.review_id) AS reviews_given
FROM users u
LEFT JOIN bookings b ON b.user_id = u.user_id
LEFT JOIN reviews r  ON r.user_id = u.user_id
GROUP BY u.user_id, u.full_name, u.email, u.phone;

-- Additional View: Daily Revenue and booking volumes
CREATE OR REPLACE VIEW v_daily_revenue AS
SELECT 
    b.booking_date,
    COUNT(b.booking_id) AS booking_count,
    SUM(b.total_amount) AS daily_revenue,
    ROUND(AVG(b.total_amount), 2) AS avg_ticket_size
FROM bookings b
WHERE b.status <> 'CANCELLED'
GROUP BY b.booking_date;

-- ---------- TRIGGER 1: prevent double booking ----------
CREATE OR REPLACE FUNCTION trg_check_overlap() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> 'CANCELLED' AND EXISTS (
        SELECT 1 FROM bookings b
        WHERE b.turf_id = NEW.turf_id
          AND b.booking_date = NEW.booking_date
          AND b.status <> 'CANCELLED'
          AND b.booking_id <> COALESCE(NEW.booking_id, -1)
          AND NEW.start_time < b.end_time
          AND NEW.end_time   > b.start_time
    ) THEN
        RAISE EXCEPTION 'This slot is already booked for the selected turf';
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_booking_overlap
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW EXECUTE FUNCTION trg_check_overlap();

-- ---------- TRIGGER 2: audit every status change ----------
CREATE OR REPLACE FUNCTION trg_audit_booking() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO booking_audit(booking_id, old_status, new_status) VALUES (NEW.booking_id, NULL, NEW.status);
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO booking_audit(booking_id, old_status, new_status) VALUES (NEW.booking_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_booking_audit
AFTER INSERT OR UPDATE ON bookings
FOR EACH ROW EXECUTE FUNCTION trg_audit_booking();

-- ---------- STORED FUNCTION: book a turf atomically ----------
CREATE OR REPLACE FUNCTION fn_book_turf(
    p_user INT, p_turf INT, p_sport INT, p_date DATE, p_start TIME, p_hours INT, p_method VARCHAR
) RETURNS INT AS $$
DECLARE
    v_price  NUMERIC;
    v_amount NUMERIC;
    v_id     INT;
BEGIN
    -- row lock on the turf serialises concurrent bookings of the same turf
    SELECT price_per_hour INTO v_price FROM turfs WHERE turf_id = p_turf AND is_active FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'This turf is not available for booking'; END IF;

    IF NOT EXISTS (SELECT 1 FROM turf_sports WHERE turf_id = p_turf AND sport_id = p_sport) THEN
        RAISE EXCEPTION 'This turf does not support the selected sport';
    END IF;
    IF p_date < CURRENT_DATE THEN RAISE EXCEPTION 'Cannot book a past date'; END IF;
    IF p_date = CURRENT_DATE AND p_start <= LOCALTIME THEN RAISE EXCEPTION 'This slot has already started'; END IF;
    IF EXTRACT(HOUR FROM p_start) + p_hours > 23 THEN RAISE EXCEPTION 'Booking must end by 11 PM'; END IF;

    -- weekend pricing: +20 %
    v_amount := v_price * p_hours * CASE WHEN EXTRACT(ISODOW FROM p_date) IN (6,7) THEN 1.2 ELSE 1 END;

    INSERT INTO bookings(user_id, turf_id, sport_id, booking_date, start_time, end_time, total_amount)
    VALUES (p_user, p_turf, p_sport, p_date, p_start, p_start + make_interval(hours => p_hours), v_amount)
    RETURNING booking_id INTO v_id;

    INSERT INTO payments(booking_id, amount, method) VALUES (v_id, v_amount, p_method);
    RETURN v_id;
END $$ LANGUAGE plpgsql;

-- ---------- STORED FUNCTION: cancel + refund ----------
CREATE OR REPLACE FUNCTION fn_cancel_booking(p_booking INT) RETURNS TEXT AS $$
DECLARE v_status TEXT; v_date DATE; v_amount NUMERIC;
BEGIN
    SELECT status, booking_date, total_amount INTO v_status, v_date, v_amount
    FROM bookings WHERE booking_id = p_booking FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
    IF v_status <> 'CONFIRMED' THEN RAISE EXCEPTION 'Only confirmed bookings can be cancelled'; END IF;
    IF v_date < CURRENT_DATE THEN RAISE EXCEPTION 'Past bookings cannot be cancelled'; END IF;

    UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking;
    UPDATE payments SET status = 'REFUNDED'  WHERE booking_id = p_booking;
    RETURN 'Booking cancelled. Refund of Rs. ' || v_amount || ' initiated.';
END $$ LANGUAGE plpgsql;

-- ---------- TRIGGER 3: validate review rating range ----------
CREATE OR REPLACE FUNCTION trg_validate_review() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.rating < 1 OR NEW.rating > 5 THEN
        RAISE EXCEPTION 'Review rating must be between 1 and 5';
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_review_validation
BEFORE INSERT OR UPDATE ON reviews
FOR EACH ROW EXECUTE FUNCTION trg_validate_review();

-- ---------- STORED FUNCTION: calculate turf total revenue ----------
CREATE OR REPLACE FUNCTION fn_calculate_turf_revenue(p_turf INT)
RETURNS NUMERIC AS $$
DECLARE
    v_rev NUMERIC;
BEGIN
    SELECT COALESCE(SUM(total_amount), 0.00) INTO v_rev
    FROM bookings
    WHERE turf_id = p_turf AND status <> 'CANCELLED';
    RETURN v_rev;
END;
$$ LANGUAGE plpgsql STABLE;

-- ---------- STORED FUNCTION: check slot availability ----------
CREATE OR REPLACE FUNCTION fn_check_slot_available(
    p_turf INT, p_date DATE, p_start TIME, p_end TIME
) RETURNS BOOLEAN AS $$
DECLARE
    v_conflict INT;
BEGIN
    SELECT COUNT(*) INTO v_conflict
    FROM bookings
    WHERE turf_id = p_turf
      AND booking_date = p_date
      AND status <> 'CANCELLED'
      AND p_start < end_time
      AND p_end > start_time;
    RETURN (v_conflict = 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- ---------- STORED FUNCTION: get customer statistics ----------
CREATE OR REPLACE FUNCTION fn_get_customer_stats(p_user INT)
RETURNS TABLE (
    user_id INT,
    customer_name VARCHAR,
    booking_count BIGINT,
    total_spent NUMERIC,
    preferred_sport VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.user_id,
        u.full_name,
        COUNT(b.booking_id) AS booking_count,
        COALESCE(SUM(b.total_amount), 0.00) AS total_spent,
        COALESCE((
            SELECT s.sport_name 
            FROM bookings b2 
            JOIN sports s ON s.sport_id = b2.sport_id 
            WHERE b2.user_id = p_user 
            GROUP BY s.sport_name 
            ORDER BY COUNT(*) DESC LIMIT 1
        ), 'None') AS preferred_sport
    FROM users u
    LEFT JOIN bookings b ON b.user_id = u.user_id AND b.status <> 'CANCELLED'
    WHERE u.user_id = p_user
    GROUP BY u.user_id, u.full_name;
END;
$$ LANGUAGE plpgsql STABLE;

-- ---------- DATA CONTROL LANGUAGE (DCL) SETUP ----------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'turf_readonly') THEN
        CREATE ROLE turf_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'turf_manager') THEN
        CREATE ROLE turf_manager NOLOGIN;
    END IF;
END $$;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO turf_readonly;
GRANT SELECT, INSERT, UPDATE ON bookings, payments, reviews TO turf_manager;
REVOKE DELETE ON bookings, payments FROM turf_manager;
