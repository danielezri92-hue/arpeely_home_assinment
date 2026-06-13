-- ============================================================
-- Approach: Before looking for flaws, I first read the query
-- to understand what it's trying to do:
-- FROM/WHERE → what data and time range 
-- GROUP BY → what's the grain (package + version + country + environment)
-- SELECT → what metrics 
-- Only then I looked for issues, in order of impact:
-- (1) partition/scan issues — most expensive
-- (2) correctness bugs — no error but wrong results
-- (3) maintainability 
-- ============================================================

-- 🔴 PERFORMANCE (critical):
-- [1] CAST on partition:
--	CAST(a.timestamp AS STRING) LIKE '2023-01-%' - so bad! Timestamp is partition -
-- casting it won’t map it to partitions and scan the full table. 
-- no need to cast - it and no need to use “like” - you can just use – timestamp>=timestamp(‘2023-01-01’) and timestamp<timestamp(‘2023-02-01’). 
-- 	(i assume you want only 01 month in 2023).


-- [2] 3 identical subqueries:
--     (SELECT COUNT(*) ... internal.file.project = a.file.project ...)
--     These subqueries depend on the outer row, so they re-execute
--     per group. All these subqueries compute the same thing (pre-2023 count
--     per project) with no partition filter. Replaced with a single
--     CTE (prev_data) that runs once with GROUP BY.


-- 🟡 CORRECTNESS (no error but wrong results):
-- [3] country_code range filter drops countries:
--     country_code > 'A' AND country_code < 'Z'
--     Not sure what the original intent was, but this filter drops countries such as 
--     ZA (South Africa). If the goal is valid country codes,
--     replaced with: REGEXP_CONTAINS(country_code, r'^[A-Z]{2}$') - looks like you did used it (REGEXP) afterwards.


-- 🟢 MAINTAINABILITY:
-- [4] 4 separate NOT LIKE conditions encoding one business rule:
--     NOT LIKE 'test-%' / NOT LIKE '%-test' / NOT LIKE 'temp-%' / NOT LIKE 'demo-%'
--     All express — hard to maintain. Consolidated into one regex:
--     NOT REGEXP_CONTAINS(file.project, r'^(test|temp|demo)-|-test$')
--     (readability fix only — similar cost).

-- [5] No CTEs — monolithic and undebuggable:
--     The query mixes filtering, aggregation, window functions and
--     correlated subqueries in one block.


-- ❓ unclear business intent (things i would check in real world):
-- [7] ORDER BY + LIMIT 1000:
--     ORDER BY + LIMIT is fine performance-wise (BigQuery applies
--     top-N optimization). However, ordering by regional_rank (a
--     per-country metric) then cutting globally at 1000 produces a
--     semantically unclear result.
-- ============================================================

WITH m_file_downloads AS ( --here i put all the base data before the agg (all the clean i took from the messy query)
SELECT
   file.project AS package_name,
   file.version AS version_string,
   country_code,
   timestamp,
   details.system.release AS sys_release,
   REGEXP_REPLACE(file.version, r'[^0-9.]', '')           AS cleaned_version_num,
   REGEXP_EXTRACT(details.python, r'^([0-9]+\.[0-9]+)')   AS python_env_version,
   CASE WHEN details.installer.name = 'pip' THEN 'Standard'
     WHEN details.installer.name IN ('bandersnatch', 'nexus', 'artifactory') THEN 'Mirror/Proxy'
     WHEN details.installer.name IS NULL THEN 'Unknown'
     ELSE 'Other-Tool'
   END AS installer_type,
   CONCAT(country_code, '-', details.distro.name, '-', details.distro.version) AS environment_fingerprint
 FROM `bigquery-public-data.pypi.file_downloads`
 WHERE timestamp >= TIMESTAMP('2023-01-01')
   AND timestamp <  TIMESTAMP('2023-02-01')
   AND details.system.name = 'Linux'
   AND details.distro.name IN ('Ubuntu', 'Debian', 'CentOS', 'Fedora')
   AND NOT REGEXP_CONTAINS(file.project, r'^(test|temp|demo)-|-test$')
   AND REGEXP_CONTAINS(country_code, r'^[A-Z]{2}$') ---assume you meant to get legit country code
),

prev_data AS (
 SELECT
   file.project AS package_name,
   COUNT(*)     AS historical_downloads
 FROM `bigquery-public-data.pypi.file_downloads`
 WHERE timestamp < TIMESTAMP('2023-01-01')
 GROUP BY package_name
),


aggregated AS (
 SELECT
   package_name,
   version_string,
   country_code,
   cleaned_version_num,
   python_env_version,
   installer_type,
   environment_fingerprint,
   COUNT(*)                                               AS total_downloads,
   SUM(CASE WHEN EXTRACT(DAYOFWEEK FROM timestamp) IN (1, 7)
THEN 1 ELSE 0 END) AS weekend_downloads,
SUM(CASE WHEN EXTRACT(DAYOFWEEK FROM timestamp) NOT IN (1, 7)
THEN 1 ELSE 0 END) AS weekday_downloads,
   MAX(timestamp)                                         AS latest_download,
   MIN(timestamp)                                         AS earliest_download_in_window,
   APPROX_COUNT_DISTINCT(sys_release)                     AS unique_sys_releases
 FROM m_file_downloads
 GROUP BY package_name, version_string, country_code,
        cleaned_version_num, python_env_version, installer_type, environment_fingerprint
 HAVING COUNT(*) > 1000
         AND weekday_downloads > weekend_downloads
),
agg_prev AS (
 SELECT
   a.*,
   COALESCE(h.historical_downloads, 0) AS historical_downloads,
   ROUND((a.total_downloads - h.historical_downloads) * 100
     / NULLIF(h.historical_downloads, 0), 2) AS growth_pct
 FROM aggregated AS a
 LEFT JOIN prev_data AS h USING (package_name) 
 --why left? the original subquery didn't filtere rows -
--  rows with no data before 2023 stayed in the output with count(*)= 0. 
-- so if now i would use inner join i would drop them; left join + COALESCE(h.historical_downloads, 0) returns the same output.
),

ranked AS (
 SELECT *,
   PERCENT_RANK() OVER (PARTITION BY country_code ORDER BY total_downloads DESC) AS regional_rank
 FROM agg_prev
)
SELECT
 package_name, version_string, historical_downloads, growth_pct,
 cleaned_version_num, python_env_version, regional_rank,weekend_downloads, weekday_downloads, installer_type,
 environment_fingerprint, latest_download, earliest_download_in_window,unique_sys_releases
FROM ranked
ORDER BY regional_rank ASC, growth_pct DESC, package_name
LIMIT 1000;
