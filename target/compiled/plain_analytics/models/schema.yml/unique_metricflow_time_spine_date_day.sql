
    
    

select
    date_day as unique_field,
    count(*) as n_records

from "plain_analytics"."main_dwh"."metricflow_time_spine"
where date_day is not null
group by date_day
having count(*) > 1


