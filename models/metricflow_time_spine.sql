{{
    config(
        materialized = 'table',
        schema = 'dwh'
    )
}}

select
    generate_series::date as date_day
from generate_series(
    '2020-01-01'::date,
    '2030-12-31'::date,
    interval 1 day
)
