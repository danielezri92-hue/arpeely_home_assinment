## Data Engineering Home Assignment: 

## Part 1: SQL Analysis Three queries (q1,q2,q3) on `bigquery-public-data.crypto_ethereum.blocks`. See inline comments for assumptions and design decisions. 

## Part 2: Query Optimization Full flaw analysis and refactor of the PyPI query (part2_optimization_challenge.sql). See file header for the structured flaw report (🔴/🟡/🟢). 

## Part 3: AI-Assisted Tool See `query_tester_agent` for full details. 


### Other DE Workflow Tools I'd Build While building this tool, I kept thinking about other tools I'd build that save time (we talked about some of these in the previous interview): **SQL Query Optimizer** The natural follow-up to Part 2 — takes a SQL query and flags common issues: non-sargable filters on partition columns, missing CTEs, and more — returning a severity-ranked report with a fixed query. **Incremental Query Template Generator** Given a table name and a timestamp column, generates an incremental query with merge logic. One of the most repetitive patterns in DE work. **EDA / Table Profiler** Before writing any pipeline or query, I always want the same things: row count, date range, sample values, and a guess at the grain and the business logic. A tool that runs this automatically on a table
