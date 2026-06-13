CREATE TABLE session_stats_by_country AS
SELECT
    country_code,
    COUNT(session_id)           AS total_sessions,
    SUM(duration_seconds)       AS total_duration_seconds,
    AVG(duration_seconds)       AS avg_duration_seconds,
    COUNT(DISTINCT user_id)     AS unique_users,
    MAX(started_at)             AS last_session_date
FROM sessions
GROUP BY country_code
