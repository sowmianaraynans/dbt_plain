
    
    

select
    agent_id as unique_field,
    count(*) as n_records

from "plain_analytics"."main_dwh"."dim_agent_workload"
where agent_id is not null
group by agent_id
having count(*) > 1


