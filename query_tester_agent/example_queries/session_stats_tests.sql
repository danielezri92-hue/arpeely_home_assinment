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
-- Source  : example_queries/session_stats.sql
-- Created : 2026-06-13 00:26
-- Tests   : 7
-- ================================================================

-- [ 1] table__row_count_positive
--      column : (table-level)
--      type   : table_level
--      reason : Result set should not be empty; zero rows usually means
--               a broken filter or missing upstream data
--      last run: PASS
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END AS failing_rows
FROM _source;

-- [ 2] table__no_duplicate_rows
--      column : (table-level)
--      type   : table_level
--      reason : Full-row duplicates indicate a join fanout or a missing
--               deduplication step upstream
--      last run: PASS
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows FROM (
    SELECT country_code, total_sessions, total_duration_seconds, avg_duration_seconds, unique_users, last_session_date, COUNT(*) AS _cnt
    FROM _source
    GROUP BY country_code, total_sessions, total_duration_seconds, avg_duration_seconds, unique_users, last_session_date
    HAVING _cnt > 1
);

-- [ 3] country_code__not_null
--      column : country_code
--      type   : not_null
--      reason : 'country_code' is a categorical field — a missing
--               country code usually signals bad or incomplete data
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE country_code IS NULL;

-- [ 4] country_code__country_code_length
--      column : country_code
--      type   : format
--      reason : 'country_code' looks like an ISO 3166 country code;
--               valid values are exactly 2 characters
--      last run: PASS
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE country_code IS NOT NULL AND LENGTH(country_code) <> 2;

-- [ 5] total_sessions__non_negative
--      column : total_sessions
--      type   : range
--      reason : 'total_sessions' is a count/amount/duration and should
--               never be negative
--      last run: PASS
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE total_sessions < 0;

-- [ 6] total_duration_seconds__non_negative
--      column : total_duration_seconds
--      type   : range
--      reason : 'total_duration_seconds' is a count/amount/duration and
--               should never be negative
--      last run: FAIL — 1 failing row(s)
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE total_duration_seconds < 0;

-- [ 7] last_session_date__not_null
--      column : last_session_date
--      type   : not_null
--      reason : 'last_session_date' is a date field — NULL dates make
--               time-based analysis unreliable
--      last run: PASS
WITH _source AS (
    SELECT country_code, COUNT(session_id) AS total_sessions, SUM(duration_seconds) AS total_duration_seconds, AVG(duration_seconds) AS avg_duration_seconds, COUNT(DISTINCT user_id) AS unique_users, MAX(started_at) AS last_session_date FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE last_session_date IS NULL;
