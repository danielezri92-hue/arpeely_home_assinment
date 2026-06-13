SELECT number, count(*) as w_records, sum(cast(w.amount AS BIGNUMERIC)) as w_amounts
FROM `bigquery-public-data.crypto_ethereum.blocks` as base cross join unnest (withdrawals) AS w -- i used cross join unnest to "open" the array into rows
where timestamp >= TIMESTAMP_SUB(current_timestamp(), INTERVAL 7 DAY) -- 7*24h back from query execution time (timestamp meaning)
group by 1
having count(*)>=5