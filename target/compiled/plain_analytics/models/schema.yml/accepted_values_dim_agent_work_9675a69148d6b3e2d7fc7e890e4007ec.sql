
    
    

with all_values as (

    select
        workload_status as value_field,
        count(*) as n_records

    from "plain_analytics"."main_dwh"."dim_agent_workload"
    group by workload_status

)

select *
from all_values
where value_field not in (
    'overloaded','busy','normal','light'
)


