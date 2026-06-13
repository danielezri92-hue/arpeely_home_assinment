-- ================================================================
-- LOCAL SETUP — DuckDB / sample data only
-- Creates one view per CSV so the tests below can run locally.
-- On a real warehouse: delete this block. The tests reference
-- your actual table names directly — nothing else to change.
-- ================================================================

CREATE OR REPLACE VIEW orders AS
    SELECT * FROM read_csv_auto('/Users/danielezri/query_tester_agent/sample_data/orders.csv');

CREATE OR REPLACE VIEW sessions AS
    SELECT * FROM read_csv_auto('/Users/danielezri/query_tester_agent/sample_data/sessions.csv');

CREATE OR REPLACE VIEW users AS
    SELECT * FROM read_csv_auto('/Users/danielezri/query_tester_agent/sample_data/users.csv');

-- ================================================================
-- Data quality tests
-- Source  : example_queries/user_order_summary.sql
-- Created : 2026-06-13 00:25
-- Tests   : 14
-- ================================================================

-- [ 1] table__row_count_positive
--      column : (table-level)
--      type   : table_level
--      reason : Result set should not be empty; zero rows usually means
--               a broken filter or missing upstream data
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END AS failing_rows
FROM _source;

-- [ 2] table__no_duplicate_rows
--      column : (table-level)
--      type   : table_level
--      reason : Full-row duplicates indicate a join fanout or a missing
--               deduplication step upstream
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows FROM (
    SELECT user_id, email, country_code, user_created_at, total_orders, total_spent, last_order_date, first_order_date, order_tenure_days, COUNT(*) AS _cnt
    FROM _source
    GROUP BY user_id, email, country_code, user_created_at, total_orders, total_spent, last_order_date, first_order_date, order_tenure_days
    HAVING _cnt > 1
);

-- [ 3] user_id__not_null
--      column : user_id
--      type   : not_null
--      reason : 'user_id' is an identifier column — a NULL here means
--               the row is unidentifiable
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE user_id IS NULL;

-- [ 4] user_id__unique
--      column : user_id
--      type   : unique
--      reason : Column name ends in '_id' — expected to be a unique
--               identifier per output row
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(user_id) - COUNT(DISTINCT user_id) AS failing_rows
FROM _source;

-- [ 5] email__not_null
--      column : email
--      type   : not_null
--      reason : 'email' is an email field — usually required for user
--               identification and communication
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE email IS NULL;

-- [ 6] email__email_format
--      column : email
--      type   : format
--      reason : 'email' looks like an email column; values should
--               contain '@' and a domain
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE email IS NOT NULL AND email NOT LIKE '%@%.%';

-- [ 7] country_code__not_null
--      column : country_code
--      type   : not_null
--      reason : 'country_code' is a categorical field — a missing
--               country code usually signals bad or incomplete data
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE country_code IS NULL;

-- [ 8] country_code__country_code_length
--      column : country_code
--      type   : format
--      reason : 'country_code' looks like an ISO 3166 country code;
--               valid values are exactly 2 characters
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE country_code IS NOT NULL AND LENGTH(country_code) <> 2;

-- [ 9] user_created_at__not_null
--      column : user_created_at
--      type   : not_null
--      reason : 'user_created_at' is a timestamp — every record should
--               have a populated event time
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE user_created_at IS NULL;

-- [10] total_orders__non_negative
--      column : total_orders
--      type   : range
--      reason : 'total_orders' is a count/amount/duration and should
--               never be negative
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE total_orders < 0;

-- [11] total_spent__non_negative
--      column : total_spent
--      type   : range
--      reason : 'total_spent' is a count/amount/duration and should
--               never be negative
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE total_spent < 0;

-- [12] last_order_date__not_null
--      column : last_order_date
--      type   : not_null
--      reason : 'last_order_date' is a date field — NULL dates make
--               time-based analysis unreliable — comes from the
--               nullable side of a LEFT JOIN, NULLs may be expected
--               here
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE last_order_date IS NULL;

-- [13] first_order_date__not_null
--      column : first_order_date
--      type   : not_null
--      reason : 'first_order_date' is a date field — NULL dates make
--               time-based analysis unreliable — comes from the
--               nullable side of a LEFT JOIN, NULLs may be expected
--               here
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE first_order_date IS NULL;

-- [14] order_tenure_days__non_negative
--      column : order_tenure_days
--      type   : range
--      reason : 'order_tenure_days' is a count/amount/duration and
--               should never be negative
--      last run: PASS
WITH _source AS (
    WITH active_users AS (
        SELECT
            user_id,
            email,
            country_code,
            created_at
        FROM users
        WHERE is_active = TRUE
    ),
    
    user_order_stats AS (
        SELECT
            user_id,
            COUNT(order_id)        AS total_orders,
            SUM(amount)            AS total_spent,
            MAX(created_at)        AS last_order_date,
            MIN(created_at)        AS first_order_date
        FROM orders
        GROUP BY user_id
    )
    
    SELECT
        u.user_id,
        u.email,
        u.country_code,
        u.created_at                            AS user_created_at,
        COALESCE(s.total_orders, 0)             AS total_orders,
        COALESCE(s.total_spent, 0.0)            AS total_spent,
        s.last_order_date,
        s.first_order_date,
        s.last_order_date - s.first_order_date  AS order_tenure_days
    FROM active_users u
    LEFT JOIN user_order_stats s ON u.user_id = s.user_id
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE order_tenure_days < 0;
