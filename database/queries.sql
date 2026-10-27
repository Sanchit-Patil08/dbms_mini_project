-- =====================================================================
--  SELECT query showcase. Each block is executed by the "DB Lab" page.
--  Format: -- @key / @category / @title / @desc, then the SQL.
-- =====================================================================

-- @key: select_where
-- @category: Basic SELECT
-- @title: WHERE, BETWEEN, ORDER BY, LIMIT
-- @desc: Active turfs priced between 800 and 1600, costliest first.
SELECT name, city, price_per_hour FROM turfs
WHERE is_active AND price_per_hour BETWEEN 800 AND 1600
ORDER BY price_per_hour DESC LIMIT 5;

-- @key: like_in
-- @category: Basic SELECT
-- @title: LIKE / ILIKE, IN, OR
-- @desc: Pattern matching and list membership.
SELECT name, area, city FROM turfs
WHERE (name ILIKE '%arena%' OR area LIKE 'B%') AND city IN ('Mumbai','Pune');

-- @key: distinct
-- @category: Basic SELECT
-- @title: DISTINCT
-- @desc: Cities where we operate.
SELECT DISTINCT city FROM turfs ORDER BY city;

-- @key: case_coalesce
-- @category: Basic SELECT
-- @title: CASE and COALESCE
-- @desc: Price tiers and a default rating for turfs with no reviews.
SELECT t.name, t.price_per_hour,
       CASE WHEN t.price_per_hour >= 1500 THEN 'Premium'
            WHEN t.price_per_hour >= 1000 THEN 'Standard' ELSE 'Budget' END AS tier,
       COALESCE((SELECT ROUND(AVG(rating),1) FROM reviews r WHERE r.turf_id = t.turf_id)::TEXT, 'No reviews yet') AS rating
FROM turfs t ORDER BY t.price_per_hour DESC;

-- @key: date_string_fn
-- @category: Basic SELECT
-- @title: Date and string functions
-- @desc: TO_CHAR, EXTRACT, UPPER, CONCAT and time arithmetic.
SELECT booking_id, UPPER(turf_name) AS turf,
       TO_CHAR(booking_date, 'Dy, DD Mon YYYY') AS day,
       CASE WHEN EXTRACT(ISODOW FROM booking_date) IN (6,7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       CONCAT(TO_CHAR(start_time,'HH24:MI'), ' - ', TO_CHAR(end_time,'HH24:MI')) AS slot,
       end_time - start_time AS duration
FROM v_booking_details ORDER BY booking_date DESC LIMIT 8;

-- @key: aggregates
-- @category: Aggregation
-- @title: COUNT, SUM, AVG, MIN, MAX
-- @desc: Overall booking statistics (cancelled bookings excluded).
SELECT COUNT(*) AS total_bookings, SUM(total_amount) AS revenue,
       ROUND(AVG(total_amount),2) AS avg_booking, MIN(total_amount) AS smallest, MAX(total_amount) AS largest
FROM bookings WHERE status <> 'CANCELLED';

-- @key: group_having
-- @category: Aggregation
-- @title: GROUP BY with HAVING
-- @desc: Turfs earning more than Rs. 3000, with booking count.
SELECT t.name, COUNT(*) AS bookings, SUM(b.total_amount) AS revenue
FROM bookings b JOIN turfs t ON t.turf_id = b.turf_id
WHERE b.status <> 'CANCELLED'
GROUP BY t.turf_id, t.name
HAVING SUM(b.total_amount) > 3000
ORDER BY revenue DESC;

-- @key: string_agg
-- @category: Aggregation
-- @title: STRING_AGG
-- @desc: All sports offered by every turf in one cell.
SELECT t.name, STRING_AGG(s.sport_name, ', ' ORDER BY s.sport_name) AS sports
FROM turfs t JOIN turf_sports ts ON ts.turf_id = t.turf_id JOIN sports s ON s.sport_id = ts.sport_id
GROUP BY t.turf_id, t.name ORDER BY t.name;

-- @key: inner_join
-- @category: Joins
-- @title: INNER JOIN (4 tables)
-- @desc: Who booked which turf for which sport.
SELECT b.booking_id, u.full_name, t.name AS turf, s.sport_name, b.booking_date, b.status
FROM bookings b
INNER JOIN users u  ON u.user_id  = b.user_id
INNER JOIN turfs t  ON t.turf_id  = b.turf_id
INNER JOIN sports s ON s.sport_id = b.sport_id
ORDER BY b.booking_date DESC;

-- @key: left_join
-- @category: Joins
-- @title: LEFT JOIN + IS NULL
-- @desc: Turfs that have never received a booking.
SELECT t.turf_id, t.name, t.city FROM turfs t
LEFT JOIN bookings b ON b.turf_id = t.turf_id
WHERE b.booking_id IS NULL;

-- @key: right_join
-- @category: Joins
-- @title: RIGHT JOIN
-- @desc: Sports that no turf offers yet.
SELECT s.sport_name FROM turf_sports ts
RIGHT JOIN sports s ON s.sport_id = ts.sport_id
WHERE ts.turf_id IS NULL;

-- @key: full_join
-- @category: Joins
-- @title: FULL OUTER JOIN
-- @desc: Every user with their booking count, including users with none.
SELECT u.full_name, COUNT(b.booking_id) AS bookings
FROM users u FULL OUTER JOIN bookings b ON b.user_id = u.user_id
GROUP BY u.user_id, u.full_name ORDER BY bookings DESC, u.full_name;

-- @key: self_join
-- @category: Joins
-- @title: SELF JOIN
-- @desc: Pairs of turfs in the same city with their price difference.
SELECT a.name AS turf_a, b.name AS turf_b, a.city, ABS(a.price_per_hour - b.price_per_hour) AS price_gap
FROM turfs a JOIN turfs b ON a.city = b.city AND a.turf_id < b.turf_id
ORDER BY a.city, price_gap DESC;

-- @key: cross_join
-- @category: Joins
-- @title: CROSS JOIN
-- @desc: Every Pune turf paired with every sport (cartesian product).
SELECT t.name AS turf, s.sport_name FROM turfs t CROSS JOIN sports s
WHERE t.city = 'Pune' ORDER BY t.name, s.sport_name;

-- @key: scalar_subquery
-- @category: Subqueries
-- @title: Scalar subquery
-- @desc: Turfs priced above the average price.
SELECT name, price_per_hour FROM turfs
WHERE price_per_hour > (SELECT AVG(price_per_hour) FROM turfs) ORDER BY price_per_hour DESC;

-- @key: in_subquery
-- @category: Subqueries
-- @title: IN subquery
-- @desc: Customers who have booked Football.
SELECT full_name, email FROM users WHERE user_id IN (
    SELECT b.user_id FROM bookings b JOIN sports s ON s.sport_id = b.sport_id WHERE s.sport_name = 'Football');

-- @key: exists_not_exists
-- @category: Subqueries
-- @title: EXISTS and NOT EXISTS
-- @desc: Users with at least one booking but no cancellation.
SELECT u.full_name FROM users u
WHERE EXISTS (SELECT 1 FROM bookings b WHERE b.user_id = u.user_id)
  AND NOT EXISTS (SELECT 1 FROM bookings c WHERE c.user_id = u.user_id AND c.status = 'CANCELLED');

-- @key: correlated
-- @category: Subqueries
-- @title: Correlated subquery
-- @desc: Latest booking date and total hours booked per turf.
SELECT t.name,
       (SELECT MAX(b.booking_date) FROM bookings b WHERE b.turf_id = t.turf_id AND b.status <> 'CANCELLED') AS last_booking,
       (SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (b.end_time - b.start_time))/3600),0)
        FROM bookings b WHERE b.turf_id = t.turf_id AND b.status <> 'CANCELLED') AS hours_booked
FROM turfs t ORDER BY hours_booked DESC;

-- @key: all_any
-- @category: Subqueries
-- @title: ALL / ANY
-- @desc: Non-Pune turfs compared against every / some Pune turf.
SELECT name, city, price_per_hour,
       CASE WHEN price_per_hour > ALL (SELECT price_per_hour FROM turfs WHERE city = 'Pune') THEN 'Costlier than all Pune turfs'
            WHEN price_per_hour < ANY (SELECT price_per_hour FROM turfs WHERE city = 'Pune') THEN 'Cheaper than some Pune turf'
            ELSE 'In between' END AS comparison
FROM turfs WHERE city <> 'Pune' ORDER BY price_per_hour DESC;

-- @key: union
-- @category: Set Operations
-- @title: UNION
-- @desc: One directory listing turfs and users together.
SELECT name AS entry, 'Turf' AS type FROM turfs
UNION
SELECT full_name, 'User' FROM users
ORDER BY type, entry;

-- @key: intersect
-- @category: Set Operations
-- @title: INTERSECT
-- @desc: Users who both booked and reviewed.
SELECT full_name FROM users WHERE user_id IN (
    SELECT user_id FROM bookings INTERSECT SELECT user_id FROM reviews);

-- @key: except
-- @category: Set Operations
-- @title: EXCEPT
-- @desc: Users who booked but never left a review.
SELECT full_name FROM users WHERE user_id IN (
    SELECT user_id FROM bookings EXCEPT SELECT user_id FROM reviews);

-- @key: cte
-- @category: CTE and Window Functions
-- @title: CTE (WITH) + percentage of total
-- @desc: Monthly revenue and each month's share.
WITH monthly AS (
    SELECT DATE_TRUNC('month', booking_date) AS m, SUM(total_amount) AS revenue
    FROM bookings WHERE status <> 'CANCELLED' GROUP BY 1)
SELECT TO_CHAR(m, 'Mon YYYY') AS month, revenue,
       ROUND(100 * revenue / SUM(revenue) OVER (), 1) AS pct_of_total
FROM monthly ORDER BY m;

-- @key: recursive_cte
-- @category: CTE and Window Functions
-- @title: Recursive CTE (hourly distribution)
-- @desc: Booking density across operating hours (06:00 to 22:00).
WITH RECURSIVE hrs(h) AS (
    SELECT 6 UNION ALL SELECT h + 1 FROM hrs WHERE h < 22)
SELECT TO_CHAR(make_time(h,0,0), 'HH24:MI') AS start_hour, COUNT(b.booking_id) AS bookings
FROM hrs LEFT JOIN bookings b
     ON EXTRACT(HOUR FROM b.start_time) = hrs.h AND b.status <> 'CANCELLED'
GROUP BY h ORDER BY h;

-- @key: window_rank
-- @category: CTE and Window Functions
-- @title: Window Function: RANK
-- @desc: Customers ranked by total spending.
SELECT u.full_name, SUM(b.total_amount) AS spent,
       RANK() OVER (ORDER BY SUM(b.total_amount) DESC) AS rank
FROM users u JOIN bookings b ON b.user_id = u.user_id
WHERE b.status <> 'CANCELLED' GROUP BY u.user_id, u.full_name;

-- @key: window_running
-- @category: CTE and Window Functions
-- @title: Window Functions: ROW_NUMBER, running SUM, LAG
-- @desc: Per-turf booking sequence, cumulative revenue and gap between bookings.
SELECT t.name, b.booking_date, b.total_amount,
       ROW_NUMBER() OVER w AS nth_booking,
       SUM(b.total_amount) OVER w AS running_revenue,
       b.booking_date - LAG(b.booking_date) OVER w AS days_since_previous
FROM bookings b JOIN turfs t ON t.turf_id = b.turf_id
WHERE b.status <> 'CANCELLED'
WINDOW w AS (PARTITION BY b.turf_id ORDER BY b.booking_date)
ORDER BY t.name, b.booking_date;

-- @key: view_turf_stats
-- @category: Views
-- @title: View: v_turf_stats
-- @desc: Consolidated view joining turfs, bookings, and reviews.
SELECT * FROM v_turf_stats ORDER BY revenue DESC;

-- @key: audit_log
-- @category: Triggers and Audit
-- @title: Trigger Audit Log
-- @desc: Status changes logged automatically by the booking audit trigger.
SELECT audit_id, booking_id, old_status, new_status, TO_CHAR(changed_at,'DD Mon HH24:MI') AS changed_at
FROM booking_audit ORDER BY audit_id DESC LIMIT 10;

-- @key: explain_index
-- @category: Query Optimization
-- @title: EXPLAIN (Index Scan)
-- @desc: Execution plan proving PostgreSQL uses the composite index idx_bookings_turf_date.
EXPLAIN SELECT * FROM bookings WHERE turf_id = 1 AND booking_date >= CURRENT_DATE AND status <> 'CANCELLED';
