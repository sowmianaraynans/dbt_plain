
    
    

with all_values as (

    select
        risk_flag as value_field,
        count(*) as n_records

    from "plain_analytics"."main_dwh"."fact_sla_performance"
    group by risk_flag

)

select *
from all_values
where value_field not in (
    'critical','warning','ok'
)


