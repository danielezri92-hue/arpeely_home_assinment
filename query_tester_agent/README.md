# query-tester-agent

## The problem

Writing data quality tests by hand for every SQL model is tedious and easy to skip. But shipping untested pipelines means null IDs, broken joins, negative counts, and bad emails silently making it to production.

This tool reads a SQL file, analyzes the output columns, and automatically suggests data quality tests — with a reason for each one. You review and approve them interactively, the tool runs them locally against sample data, prints a pass/fail report, and saves the tests as a standalone SQL file you can run on your real warehouse later.

Everything runs locally: no warehouse connection, no API keys.

---

## Install

```bash
git clone <repo>
cd query-tester-agent
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

---

## How to run

```bash
python main.py --sql <path/to/query.sql>
```

Optional flags:
- `--data <dir>` — directory with sample CSV files (default: `sample_data/`)
- `--output <file>` — where to save the generated test SQL (default: `<query>_tests.sql` next to the source)

---

## Example 1 — SELECT with CTEs and LEFT JOIN

**Query:** [`example_queries/user_order_summary.sql`](example_queries/user_order_summary.sql)

Joins active users with their aggregated order stats. Users with no orders produce NULL dates on the right side of the LEFT JOIN.

**Sample data issues planted in `users.csv` and `orders.csv`:**
- User 3 has a NULL email
- User 5 appears twice (full duplicate row — upstream dedup failure)
- User 4 has no orders → NULL `last_order_date` / `first_order_date` from the LEFT JOIN

```
$ python main.py --sql example_queries/user_order_summary.sql

Query Analysis
  CTEs found   : active_users, user_order_stats
  Contains join: yes
  Output cols  : 9

                          Suggested Tests  (14 total)
┏━━━━┳━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  # ┃ Column             ┃ Type         ┃ Reason                                            ┃
┡━━━━╇━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│  1 │ (table-level)      │ table_level  │ Result set should not be empty                    │
│  2 │ (table-level)      │ table_level  │ Full-row duplicates indicate a join fanout...     │
│  3 │ user_id            │ not_null     │ 'user_id' is an identifier column — a NULL...     │
│  4 │ user_id            │ unique       │ Column name ends in '_id' — expected to be unique │
│  5 │ email              │ not_null     │ 'email' is an email field — usually required...   │
│  6 │ email              │ format       │ 'email' looks like an email column...             │
│  7 │ country_code       │ not_null     │ 'country_code' is a categorical field...          │
│  8 │ country_code       │ format       │ 'country_code' looks like an ISO 3166 country...  │
│  9 │ user_created_at    │ not_null     │ 'user_created_at' is a timestamp...               │
│ 10 │ total_orders       │ range        │ 'total_orders' is a count/amount/duration...      │
│ 11 │ total_spent        │ range        │ 'total_spent' is a count/amount/duration...       │
│ 12 │ last_order_date    │ not_null     │ 'last_order_date' is a date field — ... comes     │
│    │                    │              │ from the nullable side of a LEFT JOIN,             │
│    │                    │              │ NULLs may be expected here                        │
│ 13 │ first_order_date   │ not_null     │ 'first_order_date' is a date field — ...LEFT JOIN │
│ 14 │ order_tenure_days  │ range        │ 'order_tenure_days' is a count/duration...        │
└────┴────────────────────┴──────────────┴───────────────────────────────────────────────────┘

? Select tests to run  (↑↓ navigate · space toggle · enter confirm):
  ◉ [ 1]  (table-level)         table_level   Result set should not be empty...
  ◉ [ 2]  (table-level)         table_level   Full-row duplicates...
  ...
  ◯ [13]  first_order_date      not_null      ... LEFT JOIN, NULLs may be expected here

Running 13 of 14 tests  (1 skipped)

Running tests...

                           Test Results
┏━━━━┳━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━┓
┃  # ┃ Column             ┃ Type         ┃ Status   ┃ Failing rows ┃
┡━━━━╇━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━┩
│  1 │ (table-level)      │ table_level  │ ✓ PASS   │            0 │
│  2 │ (table-level)      │ table_level  │ ✗ FAIL   │            1 │  ← user 5 duplicated
│  3 │ user_id            │ not_null     │ ✓ PASS   │            0 │
│  4 │ user_id            │ unique       │ ✗ FAIL   │            1 │  ← user 5 duplicated
│  5 │ email              │ not_null     │ ✗ FAIL   │            1 │  ← user 3 NULL email
│  6 │ email              │ format       │ ✓ PASS   │            0 │
│  7 │ country_code       │ not_null     │ ✓ PASS   │            0 │
│  8 │ country_code       │ format       │ ✓ PASS   │            0 │
│  9 │ user_created_at    │ not_null     │ ✓ PASS   │            0 │
│ 10 │ total_orders       │ range        │ ✓ PASS   │            0 │
│ 11 │ total_spent        │ range        │ ✓ PASS   │            0 │
│ 12 │ last_order_date    │ not_null     │ ✗ FAIL   │            1 │  ← user 4 no orders
│ 14 │ order_tenure_days  │ range        │ ✓ PASS   │            0 │
└────┴────────────────────┴──────────────┴──────────┴──────────────┘
  9 passed  ·  4 failed

Test SQL saved to: example_queries/user_order_summary_tests.sql
```

**Note on tests 12–13:** The LEFT JOIN warning is shown in the suggestion reason. The user skipped test 13 in the approval step because NULL dates are expected for users with no orders — that's a business logic call, not a data error.

---

## Example 2 — CREATE TABLE with GROUP BY, no join

**Query:** [`example_queries/session_stats.sql`](example_queries/session_stats.sql)

Aggregates session data by country. The tool handles `CREATE TABLE ... AS SELECT` by extracting the SELECT for test generation — the saved test SQL runs on any warehouse without modification.

**Sample data issues planted in `sessions.csv`:**
- Session s009 has a NULL `country_code`
- Session s007 has `duration_seconds = -500`, making the CA group's `total_duration_seconds` go negative

```
$ python main.py --sql example_queries/session_stats.sql

Query Analysis
  CTEs found   : none
  Contains join: no
  Output cols  : 6

                         Suggested Tests  (7 total)
┏━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  # ┃ Column                 ┃ Type         ┃ Reason                               ┃
┡━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│  1 │ (table-level)          │ table_level  │ Result set should not be empty       │
│  2 │ (table-level)          │ table_level  │ Full-row duplicates indicate...       │
│  3 │ country_code           │ not_null     │ 'country_code' is a categorical field │
│  4 │ country_code           │ format       │ ISO 3166 country code; valid values  │
│    │                        │              │ are exactly 2 characters             │
│  5 │ total_sessions         │ range        │ count/amount/duration, never negative │
│  6 │ total_duration_seconds │ range        │ count/amount/duration, never negative │
│  7 │ last_session_date      │ not_null     │ 'last_session_date' is a date field  │
└────┴────────────────────────┴──────────────┴──────────────────────────────────────┘

Running tests...

                             Test Results
┏━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━┓
┃  # ┃ Column                 ┃ Type         ┃ Status   ┃ Failing rows ┃
┡━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━┩
│  1 │ (table-level)          │ table_level  │ ✓ PASS   │            0 │
│  2 │ (table-level)          │ table_level  │ ✓ PASS   │            0 │
│  3 │ country_code           │ not_null     │ ✗ FAIL   │            1 │  ← s009 NULL country
│  4 │ country_code           │ format       │ ✓ PASS   │            0 │
│  5 │ total_sessions         │ range        │ ✓ PASS   │            0 │
│  6 │ total_duration_seconds │ range        │ ✗ FAIL   │            1 │  ← CA = 180 + (-500)
│  7 │ last_session_date      │ not_null     │ ✓ PASS   │            0 │
└────┴────────────────────────┴──────────────┴──────────┴──────────────┘
  5 passed  ·  2 failed

Test SQL saved to: example_queries/session_stats_tests.sql
```

---

## The exported SQL file

Each `_tests.sql` file has two sections:

**LOCAL SETUP block** (top) — `CREATE OR REPLACE VIEW` statements that map CSV files to table names so you can run the file directly in DuckDB. On a real warehouse, delete this block and nothing else changes.

```sql
-- LOCAL SETUP — DuckDB / sample data only
-- On a real warehouse: delete this block. The tests reference
-- your actual table names directly — nothing else to change.

CREATE OR REPLACE VIEW sessions AS
    SELECT * FROM read_csv_auto('/path/to/sample_data/sessions.csv');
```

**Test blocks** — one per approved test, each with its reason as a comment and `failing_rows` as the return value (0 = pass):

```sql
-- [ 3] country_code__not_null
--      column   : country_code
--      type     : not_null
--      reason   : 'country_code' is a categorical field — a missing country
--                 code usually signals bad or incomplete data
--      last run : FAIL — 1 failing row(s)
WITH _source AS (
    SELECT country_code, ... FROM sessions GROUP BY country_code
)
SELECT COUNT(*) AS failing_rows
FROM _source
WHERE country_code IS NULL;
```

---

## How the suggestion heuristics work

The tool inspects each output column name and expression and applies these rules:

| Pattern | Test generated | Example trigger |
|---|---|---|
| Column name ends in `_id` or is `id` | **unique** + **not_null** | `user_id`, `order_id` |
| Column name contains `email` | **not_null** + **email format** (`LIKE '%@%.%'`) | `email`, `user_email` |
| Column name matches `country_code` or `country` | **not_null** + **length = 2** (ISO 3166) | `country_code` |
| Column name ends in `_at` | **not_null** (timestamp) | `created_at`, `updated_at` |
| Column name ends in `_date` | **not_null** (date field) | `last_order_date` |
| Column name starts with `total_`, `num_`, `count_` or ends in `_count`, `_orders`, `_amount`, `_spent`, `_days`, `_revenue`, `_price` | **non-negative** range check | `total_orders`, `order_tenure_days` |
| Expression starts with `COALESCE(...)` | NOT NULL test **skipped** — already protected | `COALESCE(total_orders, 0)` |
| Column's source table alias is on the right side of a LEFT JOIN | NOT NULL suggested with a **warning** | `last_order_date` from `LEFT JOIN orders` |
| Always (table-level) | **row count > 0** + **no duplicate full rows** | — |

The suggestions are always shown with their reason before anything runs. You approve or skip each one interactively — the tool never runs tests blindly.
