-- * No time constraint specified - so the query runs on full table (better to provide date range).
-- * The curren day reflects partial data
-- I used row_number instead of rank() or dense_rank() - since they would act diff on ties (1,1,3 or 1,1,2 where row_number just do 1,2,3) 


with pop as (
SELECT date(timestamp) as calendar_day ,number, gas_used, row_number() over(partition by date(timestamp) order by gas_used desc) as rn 
FROM `bigquery-public-data.crypto_ethereum.blocks` as base
)
select *
from pop
where rn <=3
