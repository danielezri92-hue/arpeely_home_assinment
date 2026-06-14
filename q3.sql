-- Assumptions & notes:
-- "Absolute change" = not sure what is the meaning of abs() - so i kept the result as: total_blocks-prev_total_blocks to keep the sign (trend direction as the question description). If do need the real 
-- absolut so i would use abs(total_blocks-prev_total_blocks).
-- * "Last 3 days of available data": filtered to MAX(calendar_day) and not today's date — so the query stays correct even if the dataset hasn't been loaded yet for today.
-- * 7-day (and not 3 in pop cte) - so LAG() can see the day preceding the displayed window.
-- * NULLIF - to be sure we are not divide by zero/

with pop as (
SELECT date(timestamp) as calendar_day, count(number) as total_blocks, sum(gas_used) as total_gas_used
FROM `bigquery-public-data.crypto_ethereum.blocks` as base
where timestamp >= TIMESTAMP_SUB(current_timestamp(), INTERVAL 7 DAY)
     and timestamp <  TIMESTAMP(current_date()) --because it's timestamp and it can be partial date
group by 1
)
, prev_day as (
select *, lag(pop.total_blocks) over(order by pop.calendar_day) as prev_total_blocks,
         lag(pop.total_gas_used) over(order by pop.calendar_day) as prev_total_gas_used
from pop
)
select calendar_day,total_blocks,total_gas_used,
         total_blocks-prev_total_blocks as absolute_total_blocks,
         total_gas_used-prev_total_gas_used as absolute_total_gas_used,
         round((total_blocks-prev_total_blocks)*100/NULLIF(prev_total_blocks, 0),2) as prec_total_blocks,
         round((total_gas_used-prev_total_gas_used)*100/NULLIF(prev_total_gas_used, 0),2) as prec_total_gas_used
from prev_day
WHERE calendar_day > DATE_SUB((select max(calendar_day) from pop), interval 3 day)

-- Production considerations (not implemented to keep scope focused):
-- All queries: use params and not dates hardcoded
