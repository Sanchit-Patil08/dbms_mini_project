-- =====================================================================
--  TurfZone DB Lab: SQL Query Showcase & Concept Demonstrations
--  Each block is loaded dynamically and executed by the "DB Lab" page.
--  Format: -- @key / @category / @title / @desc, then the SQL statement.
-- =====================================================================

-- =====================================================================
--  SECTION 1: DQL (Data Query Language)
-- =====================================================================

-- @key: dql_select_filter
-- @category: DQL (Data Query Language)
-- @title: DQL: WHERE, BETWEEN, IN, ORDER BY, LIMIT
-- @desc: Filter active turfs priced between 800 and 1600 in Mumbai and Pune, sorted by price.
SELECT name, city, area, price_per_hour, capacity
FROM turfs
WHERE is_active = TRUE 
  AND price_per_hour BETWEEN 800 AND 1600
  AND city IN ('Mumbai', 'Pune')
ORDER BY price_per_hour DESC, name ASC
LIMIT 10;

-- @key: dql_pattern_matching
-- @category: DQL (Data Query Language)
-- @title: DQL: LIKE / ILIKE Pattern Matching & Wildcards
-- @desc: Case-insensitive search for turf names containing 'arena' or areas starting with 'B'.
SELECT turf_id, name, area, city, price_per_hour
FROM turfs
WHERE name ILIKE '%arena%' OR area LIKE 'B%'
ORDER BY name;

-- @key: dql_distinct_data
-- @category: DQL (Data Query Language)
-- @title: DQL: DISTINCT Data Selection
-- @desc: List unique cities and areas where turf facilities are currently operating.
SELECT DISTINCT city, area 
FROM turfs 
ORDER BY city, area;

-- @key: dql_case_coalesce
-- @category: DQL (Data Query Language)
-- @title: DQL: CASE Expressions and COALESCE
-- @desc: Categorize turfs into price tiers and supply a fallback for turfs without reviews.
SELECT t.name, t.city, t.price_per_hour,
       CASE WHEN t.price_per_hour >= 1500 THEN 'Premium Tier'
            WHEN t.price_per_hour >= 1000 THEN 'Standard Tier'
            ELSE 'Budget Friendly' END AS pricing_tier,
       COALESCE((SELECT ROUND(AVG(rating), 1)::TEXT FROM reviews r WHERE r.turf_id = t.turf_id), 'No reviews yet') AS customer_rating
FROM turfs t 
ORDER BY t.price_per_hour DESC;

-- @key: dql_date_time_fn
-- @category: DQL (Data Query Language)
-- @title: DQL: Date and String Manipulation Functions
-- @desc: Format booking dates, calculate day types (Weekend/Weekday), slot strings, and durations.
SELECT booking_id, UPPER(turf_name) AS turf,
       TO_CHAR(booking_date, 'Dy, DD Mon YYYY') AS formatted_date,
       CASE WHEN EXTRACT(ISODOW FROM booking_date) IN (6,7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       CONCAT(TO_CHAR(start_time, 'HH24:MI'), ' - ', TO_CHAR(end_time, 'HH24:MI')) AS time_slot,
       end_time - start_time AS duration,
       total_amount
FROM v_booking_details 
ORDER BY booking_date DESC 
LIMIT 8;


-- =====================================================================
--  SECTION 2: Aggregate Functions - GROUP BY & HAVING
-- =====================================================================

-- @key: agg_summary_stats
-- @category: Aggregate Functions (GROUP BY, HAVING)
-- @title: Aggregates: COUNT, SUM, AVG, MIN, MAX
-- @desc: High-level financial and operational summary across all active bookings.
SELECT COUNT(*) AS total_bookings,
       SUM(total_amount) AS gross_revenue,
       ROUND(AVG(total_amount), 2) AS average_ticket_size,
       MIN(total_amount) AS lowest_booking,
       MAX(total_amount) AS highest_booking
FROM bookings 
WHERE status <> 'CANCELLED';

-- @key: agg_group_by_having
-- @category: Aggregate Functions (GROUP BY, HAVING)
-- @title: GROUP BY with HAVING (Revenue Threshold)
-- @desc: Identify top revenue-generating turfs that have made more than Rs. 3,000 in bookings.
SELECT t.name AS turf_name, t.city,
       COUNT(b.booking_id) AS confirmed_bookings,
       SUM(b.total_amount) AS total_revenue,
       ROUND(AVG(b.total_amount), 2) AS avg_booking_amount
FROM bookings b 
JOIN turfs t ON t.turf_id = b.turf_id
WHERE b.status <> 'CANCELLED'
GROUP BY t.turf_id, t.name, t.city
HAVING SUM(b.total_amount) > 3000
ORDER BY total_revenue DESC;

-- @key: agg_multi_group_having
-- @category: Aggregate Functions (GROUP BY, HAVING)
-- @title: Multi-Column GROUP BY with Multi-Condition HAVING
-- @desc: Aggregate booking metrics by City and Sport, displaying only categories with multiple bookings.
SELECT t.city, s.sport_name,
       COUNT(b.booking_id) AS total_sessions,
       SUM(b.total_amount) AS total_spent,
       ROUND(AVG(b.total_amount), 2) AS avg_session_cost
FROM bookings b
JOIN turfs t  ON t.turf_id = b.turf_id
JOIN sports s ON s.sport_id = b.sport_id
WHERE b.status <> 'CANCELLED'
GROUP BY t.city, s.sport_name
HAVING COUNT(b.booking_id) >= 1 AND SUM(b.total_amount) >= 1000
ORDER BY t.city, total_spent DESC;

-- @key: agg_string_aggregate
-- @category: Aggregate Functions (GROUP BY, HAVING)
-- @title: Aggregation: STRING_AGG List Concatenation
-- @desc: Concatenate all supported sports for each turf into a single grouped row.
SELECT t.name AS turf_name, t.city,
       COUNT(s.sport_id) AS supported_sports_count,
       STRING_AGG(s.sport_name, ', ' ORDER BY s.sport_name) AS available_sports
FROM turfs t 
JOIN turf_sports ts ON ts.turf_id = t.turf_id 
JOIN sports s ON s.sport_id = ts.sport_id
GROUP BY t.turf_id, t.name, t.city 
ORDER BY t.city, t.name;


-- =====================================================================
--  SECTION 3: Views in SQL
-- =====================================================================

-- @key: view_booking_details
-- @category: Views in SQL
-- @title: Querying View: v_booking_details
-- @desc: Denormalized view joining users, turfs, sports, and payments for unified booking data.
SELECT booking_id, full_name, email, turf_name, city, sport_name, booking_date, start_time, end_time, total_amount, status, payment_method, payment_status
FROM v_booking_details
WHERE status = 'CONFIRMED'
ORDER BY booking_date DESC, start_time DESC
LIMIT 10;

-- @key: view_turf_stats
-- @category: Views in SQL
-- @title: Querying View: v_turf_stats (Performance Aggregation)
-- @desc: Analytical view aggregating booking counts, gross revenue, review counts, and average ratings.
SELECT turf_id, name, city, price_per_hour, total_bookings, revenue, avg_rating, review_count
FROM v_turf_stats
ORDER BY revenue DESC, avg_rating DESC;

-- @key: view_customer_summary
-- @category: Views in SQL
-- @title: Querying View: v_customer_summary (Customer Lifetime Value)
-- @desc: View aggregating customer booking history, completed games, total spending, and reviews given.
SELECT user_id, full_name, email, phone, total_bookings, completed_bookings, total_spent, reviews_given
FROM v_customer_summary
ORDER BY total_spent DESC;

-- @key: view_daily_revenue
-- @category: Views in SQL
-- @title: Querying View: v_daily_revenue (Time-Series View)
-- @desc: Trend view analyzing day-by-day revenue, volume of bookings, and average transaction size.
SELECT booking_date, booking_count, daily_revenue, avg_ticket_size
FROM v_daily_revenue
ORDER BY booking_date DESC
LIMIT 10;

-- @key: view_catalog_metadata
-- @category: Views in SQL
-- @title: Views Metadata & Catalog Inspection
-- @desc: Inspect all user-defined database views registered in the PostgreSQL information_schema.
SELECT table_name AS view_name, is_updatable, check_option, is_insertable_into
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;


-- =====================================================================
--  SECTION 4: Joins
-- =====================================================================

-- @key: join_inner_multi
-- @category: Joins
-- @title: INNER JOIN (4 Relational Tables)
-- @desc: Combine users, bookings, turfs, and sports to see confirmed session details.
SELECT b.booking_id, u.full_name AS customer, t.name AS turf_name, s.sport_name,
       b.booking_date, b.start_time, b.total_amount, b.status
FROM bookings b
INNER JOIN users u  ON u.user_id  = b.user_id
INNER JOIN turfs t  ON t.turf_id  = b.turf_id
INNER JOIN sports s ON s.sport_id = b.sport_id
WHERE b.status = 'CONFIRMED'
ORDER BY b.booking_date DESC;

-- @key: join_left_outer
-- @category: Joins
-- @title: LEFT OUTER JOIN + IS NULL
-- @desc: Retrieve all turfs and their booking counts, highlighting turfs that have zero bookings.
SELECT t.turf_id, t.name AS turf_name, t.city, t.price_per_hour,
       COUNT(b.booking_id) AS bookings_count,
       CASE WHEN COUNT(b.booking_id) = 0 THEN 'No Bookings Yet' ELSE 'Active' END AS activity_status
FROM turfs t
LEFT JOIN bookings b ON b.turf_id = t.turf_id
GROUP BY t.turf_id, t.name, t.city, t.price_per_hour
ORDER BY bookings_count ASC, t.name;

-- @key: join_right_outer
-- @category: Joins
-- @title: RIGHT OUTER JOIN
-- @desc: Identify all sports defined in the system and discover which sports are not yet hosted by any turf.
SELECT s.sport_id, s.sport_name,
       COUNT(ts.turf_id) AS hosting_turfs_count,
       CASE WHEN COUNT(ts.turf_id) = 0 THEN 'Unassigned Sport' ELSE 'Offered' END AS offering_status
FROM turf_sports ts
RIGHT JOIN sports s ON s.sport_id = ts.sport_id
GROUP BY s.sport_id, s.sport_name
ORDER BY hosting_turfs_count ASC, s.sport_name;

-- @key: join_full_outer
-- @category: Joins
-- @title: FULL OUTER JOIN
-- @desc: Comprehensive pairing of all registered users with their bookings, including users without bookings.
SELECT u.user_id, u.full_name, u.email,
       COUNT(b.booking_id) AS booking_count,
       COALESCE(SUM(b.total_amount), 0.00) AS total_spent
FROM users u
FULL OUTER JOIN bookings b ON b.user_id = u.user_id
GROUP BY u.user_id, u.full_name, u.email
ORDER BY booking_count DESC, u.full_name;

-- @key: join_self
-- @category: Joins
-- @title: SELF JOIN: Price & Capacity Gap Analysis
-- @desc: Compare pairs of turfs within the same city to evaluate pricing competition and rate differences.
SELECT a.city,
       a.name AS turf_1, a.price_per_hour AS price_1,
       b.name AS turf_2, b.price_per_hour AS price_2,
       ABS(a.price_per_hour - b.price_per_hour) AS price_difference
FROM turfs a 
JOIN turfs b ON a.city = b.city AND a.turf_id < b.turf_id
ORDER BY a.city, price_difference DESC;

-- @key: join_cross
-- @category: Joins
-- @title: CROSS JOIN: Cartesian Product Analysis
-- @desc: Cross product between cities and sports to determine potential market expansion opportunities.
SELECT DISTINCT t.city, s.sport_name
FROM turfs t 
CROSS JOIN sports s
ORDER BY t.city, s.sport_name;


-- =====================================================================
--  SECTION 5: Data Control Commands (DCL)
-- =====================================================================

-- @key: dcl_table_privileges
-- @category: Data Control Commands (DCL)
-- @title: DCL: Audit Table & View Privileges
-- @desc: Query information_schema.table_privileges to verify permissions granted to database roles.
SELECT grantee, table_name, privilege_type, is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public' 
  AND grantee IN ('turf_readonly', 'turf_manager', 'postgres', 'PUBLIC')
  AND table_name IN ('bookings', 'turfs', 'payments', 'reviews', 'v_turf_stats', 'v_booking_details')
ORDER BY table_name, grantee, privilege_type;

-- @key: dcl_role_attributes
-- @category: Data Control Commands (DCL)
-- @title: DCL: Inspect System Roles & Security Attributes
-- @desc: Inspect custom roles (turf_readonly, turf_manager) and their authorization flags in pg_roles.
SELECT rolname AS role_name,
       rolsuper AS is_superuser,
       rolinherit AS can_inherit_privileges,
       rolcreaterole AS can_create_roles,
       rolcreatedb AS can_create_databases,
       rolcanlogin AS can_login
FROM pg_roles
WHERE rolname IN ('turf_readonly', 'turf_manager', 'postgres')
ORDER BY rolname;

-- @key: dcl_role_grants
-- @category: Data Control Commands (DCL)
-- @title: DCL: Active Role Memberships and Hierarchy
-- @desc: Inspect applicable role memberships and administrative authorization hierarchy.
SELECT grantee, role_name, is_grantable
FROM information_schema.applicable_roles
ORDER BY grantee, role_name;

-- @key: dcl_syntax_demo
-- @category: Data Control Commands (DCL)
-- @title: DCL: GRANT and REVOKE Command Specifications
-- @desc: Reference showcase demonstrating exact syntax and security impact of GRANT and REVOKE commands.
SELECT 'GRANT SELECT ON v_turf_stats, v_booking_details, v_customer_summary TO turf_readonly;' AS sample_grant_command,
       'GRANT SELECT, INSERT, UPDATE ON bookings, payments, reviews TO turf_manager;' AS sample_table_grant,
       'REVOKE DELETE ON bookings, payments FROM turf_manager;' AS sample_revoke_command,
       'Enforces Least Privilege: Managers can read/write bookings but cannot hard-delete financial records.' AS security_policy_note;


-- =====================================================================
--  SECTION 6: Triggers
-- =====================================================================

-- @key: trg_audit_log_output
-- @category: Triggers
-- @title: Trigger Output: Real-Time Audit Log (booking_audit)
-- @desc: View change history rows created automatically by the AFTER UPDATE trigger (trg_booking_audit).
SELECT audit_id, booking_id, old_status, new_status,
       TO_CHAR(changed_at, 'DD Mon YYYY HH24:MI:SS') AS timestamp_logged
FROM booking_audit
ORDER BY audit_id DESC
LIMIT 15;

-- @key: trg_inspect_triggers
-- @category: Triggers
-- @title: Triggers: Catalog Inspection from information_schema
-- @desc: Discover all active triggers, their firing events (INSERT/UPDATE), timing, and target tables.
SELECT trigger_name,
       event_manipulation AS trigger_event,
       event_object_table AS target_table,
       action_timing AS execution_timing,
       action_orientation AS orientation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- @key: trg_function_definition
-- @category: Triggers
-- @title: Triggers: PL/pgSQL Trigger Function Definitions
-- @desc: View the source code of the trigger functions that enforce double-booking prevention and audit logging.
SELECT p.proname AS trigger_function_name,
       pg_get_functiondef(p.oid) AS full_function_source
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname IN ('trg_check_overlap', 'trg_audit_booking', 'trg_validate_review');

-- @key: trg_double_booking_guard
-- @category: Triggers
-- @title: Triggers: BEFORE INSERT Overlap Prevention Logic
-- @desc: Shows how trg_booking_overlap guards against slot conflicts and double bookings.
SELECT 'trg_booking_overlap' AS trigger_name,
       'BEFORE INSERT OR UPDATE' AS firing_timing,
       'bookings' AS target_table,
       'Prevents overlapping start_time and end_time for the same turf on the same date.' AS description;


-- =====================================================================
--  SECTION 7: PL/SQL (Stored Functions & Procedures)
-- =====================================================================

-- @key: plsql_call_revenue_fn
-- @category: PLSQL
-- @title: PL/SQL: Function Call - fn_calculate_turf_revenue
-- @desc: Execute custom PL/pgSQL function to compute confirmed gross revenue for each turf.
SELECT t.turf_id, t.name AS turf_name, t.city,
       fn_calculate_turf_revenue(t.turf_id) AS calculated_revenue
FROM turfs t
ORDER BY calculated_revenue DESC;

-- @key: plsql_call_availability
-- @category: PLSQL
-- @title: PL/SQL: Function Call - fn_check_slot_available
-- @desc: Execute PL/pgSQL boolean availability checker for upcoming slots without hardcoding logic in frontend.
SELECT t.turf_id, t.name AS turf_name,
       CURRENT_DATE + 1 AS check_date,
       TIME '18:00' AS start_time,
       TIME '20:00' AS end_time,
       fn_check_slot_available(t.turf_id, CURRENT_DATE + 1, TIME '18:00', TIME '20:00') AS is_slot_available
FROM turfs t
WHERE t.is_active = TRUE
LIMIT 6;

-- @key: plsql_call_customer_stats
-- @category: PLSQL
-- @title: PL/SQL: Table-Returning Function - fn_get_customer_stats
-- @desc: Call PL/pgSQL function that returns a table of aggregated metrics for customer #3.
SELECT * FROM fn_get_customer_stats(3);

-- @key: plsql_inspect_routines
-- @category: PLSQL
-- @title: PL/SQL: Stored Routines & Argument Signatures
-- @desc: Discover all PL/pgSQL stored functions and procedures defined in the application database.
SELECT p.proname AS routine_name,
       pg_get_function_arguments(p.oid) AS argument_list,
       pg_get_function_result(p.oid) AS return_type,
       l.lanname AS language
FROM pg_proc p
JOIN pg_language l ON l.oid = p.prolang
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND l.lanname = 'plpgsql'
ORDER BY p.proname;

-- @key: plsql_fn_booking_logic
-- @category: PLSQL
-- @title: PL/SQL: Atomic Booking Function (fn_book_turf)
-- @desc: Inspect the production PL/pgSQL booking engine implementing transaction management and row locks.
SELECT proname AS function_name, pg_get_functiondef(oid) AS source_code
FROM pg_proc
WHERE proname = 'fn_book_turf';


-- =====================================================================
--  SECTION 8: Transactions from SQL (TCL)
-- =====================================================================

-- @key: tcl_tx_status
-- @category: Transaction from sql
-- @title: TCL: Inspect Current Transaction State & Isolation Level
-- @desc: Query transaction ID, current isolation level, and transaction mode.
SELECT txid_current() AS current_transaction_xid,
       current_setting('transaction_isolation') AS isolation_level,
       current_setting('transaction_read_only') AS is_read_only_mode,
       NOW() AS transaction_start_timestamp;

-- @key: tcl_active_locks
-- @category: Transaction from sql
-- @title: TCL: Row-Level Locks & Concurrency Inspection (pg_locks)
-- @desc: Monitor active transactional locks ensuring ACID compliance during high-concurrency booking.
SELECT l.locktype,
       l.relation::regclass AS locked_relation,
       l.mode AS lock_mode,
       l.granted AS is_granted,
       l.pid AS process_id
FROM pg_locks l
WHERE l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND l.relation IS NOT NULL
LIMIT 10;

-- @key: tcl_workflow_demo
-- @category: Transaction from sql
-- @title: TCL: Multi-Stage Transaction with SAVEPOINT & ROLLBACK
-- @desc: Live demonstration of transactional workflow showing atomic consistency and error recovery.
SELECT 'BEGIN; -- Step 1: Start Transaction' AS step_1,
       'INSERT INTO bookings (...) VALUES (...);' AS step_2,
       'SAVEPOINT payment_verification; -- Step 3: Checkpoint' AS step_3,
       'INSERT INTO payments (...) VALUES (...);' AS step_4,
       'ROLLBACK TO SAVEPOINT payment_verification; -- Step 5: Undo payment on failure' AS step_5,
       'COMMIT; -- Step 6: Atomic Finalization' AS step_6;


-- =====================================================================
--  SECTION 9: Advanced Subqueries & Set Operations
-- =====================================================================

-- @key: scalar_subquery
-- @category: Subqueries
-- @title: Scalar Subquery
-- @desc: Find turfs priced strictly above the system-wide average hourly rate.
SELECT name, city, price_per_hour
FROM turfs
WHERE price_per_hour > (SELECT AVG(price_per_hour) FROM turfs)
ORDER BY price_per_hour DESC;

-- @key: in_subquery
-- @category: Subqueries
-- @title: IN Subquery
-- @desc: Customers who have booked Football sessions.
SELECT full_name, email, phone 
FROM users 
WHERE user_id IN (
    SELECT b.user_id 
    FROM bookings b 
    JOIN sports s ON s.sport_id = b.sport_id 
    WHERE s.sport_name = 'Football'
);

-- @key: exists_not_exists
-- @category: Subqueries
-- @title: EXISTS and NOT EXISTS
-- @desc: Loyal users who have made at least one booking and never had a cancellation.
SELECT u.user_id, u.full_name, u.email
FROM users u
WHERE EXISTS (SELECT 1 FROM bookings b WHERE b.user_id = u.user_id)
  AND NOT EXISTS (SELECT 1 FROM bookings c WHERE c.user_id = u.user_id AND c.status = 'CANCELLED');

-- @key: union_operations
-- @category: Set Operations
-- @title: UNION Set Operation
-- @desc: Combined master directory of turf venues and users.
SELECT name AS entity_name, city AS entity_location, 'Turf Venue' AS entity_type 
FROM turfs
UNION
SELECT full_name, 'Registered Customer', 'User Account' 
FROM users
ORDER BY entity_type, entity_name;

-- @key: intersect_operations
-- @category: Set Operations
-- @title: INTERSECT Set Operation
-- @desc: Identify users who have actively booked turfs AND also submitted feedback reviews.
SELECT full_name, email 
FROM users 
WHERE user_id IN (
    SELECT user_id FROM bookings 
    INTERSECT 
    SELECT user_id FROM reviews
);

-- @key: cte_window_rank
-- @category: CTE and Window Functions
-- @title: CTE and Window Function (RANK)
-- @desc: Rank customers by their lifetime spending on turf bookings.
WITH customer_spending AS (
    SELECT u.user_id, u.full_name, SUM(b.total_amount) AS total_spent
    FROM users u
    JOIN bookings b ON b.user_id = u.user_id
    WHERE b.status <> 'CANCELLED'
    GROUP BY u.user_id, u.full_name
)
SELECT full_name, total_spent,
       RANK() OVER (ORDER BY total_spent DESC) AS spend_rank,
       ROUND(100.0 * total_spent / SUM(total_spent) OVER (), 1) AS pct_of_total_turnover
FROM customer_spending
ORDER BY spend_rank;

-- @key: explain_plan
-- @category: Query Execution Plan (EXPLAIN)
-- @title: EXPLAIN Query Execution Plan
-- @desc: Inspect the query execution plan generated by PostgreSQL optimizer for turf slot lookups.
EXPLAIN SELECT * FROM bookings WHERE turf_id = 1 AND booking_date >= CURRENT_DATE AND status <> 'CANCELLED';
