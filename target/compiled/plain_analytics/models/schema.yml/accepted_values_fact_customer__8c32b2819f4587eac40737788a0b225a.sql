
    
    

with all_values as (

    select
        company_tier as value_field,
        count(*) as n_records

    from "plain_analytics"."main_dwh"."fact_customer_cohorts"
    group by company_tier

)

select *
from all_values
where value_field not in (
    'enterprise','pro','starter','free'
)


