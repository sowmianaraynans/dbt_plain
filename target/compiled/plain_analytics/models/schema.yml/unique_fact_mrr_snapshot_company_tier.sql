
    
    

select
    company_tier as unique_field,
    count(*) as n_records

from "plain_analytics"."main_dwh"."fact_mrr_snapshot"
where company_tier is not null
group by company_tier
having count(*) > 1


