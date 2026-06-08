-- stg_customers.sql
-- Cleaned, typed, and renamed from raw_customers.
-- Deduplication: keep the most recently updated record per customer id.
-- This is the safe-to-join version — all downstream models use this, not raw.

with source as (
    select * from "plain_analytics"."main_raw"."raw_customers"
),

deduped as (
    select *,
        row_number() over (
            partition by id
            order by updated_at desc
        ) as rn
    from source
),

final as (
    select
        id                                          as customer_id,
        full_name,
        short_name,
        email,
        company_id,
        tenant_id,
        company_tier,
        is_spam::boolean                            as is_spam,
        status,
        status = 'active'                           as is_active,
        status = 'churned'                          as is_churned,
        created_at::timestamp                       as created_at,
        updated_at::timestamp                       as updated_at,
        date_trunc('month', created_at::timestamp)  as cohort_month
    from deduped
    where rn = 1
      and is_spam = false
)

select * from final