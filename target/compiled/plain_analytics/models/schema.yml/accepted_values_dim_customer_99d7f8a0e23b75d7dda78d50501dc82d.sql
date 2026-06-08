
    
    

with all_values as (

    select
        customer_status as value_field,
        count(*) as n_records

    from "plain_analytics"."main_dwh"."dim_customer"
    group by customer_status

)

select *
from all_values
where value_field not in (
    'active','idle','churned'
)


