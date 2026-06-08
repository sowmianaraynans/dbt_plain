-- stg_companies.sql
-- Cleaned company (account) records.
-- Companies map to B2B accounts — the account-level unit for GTM and CSM.

with source as (
    select * from "plain_analytics"."main_raw"."raw_companies"
),

deduped as (
    select *,
        row_number() over (partition by id order by updated_at desc) as rn
    from source
),

final as (
    select
        id                                          as company_id,
        name                                        as company_name,
        domain_name,
        tier                                        as company_tier,
        region,
        is_active::boolean                          as is_active,
        mrr_usd::integer                            as mrr_usd,
        tier in ('enterprise', 'pro')               as is_paying,
        tier = 'enterprise'                         as is_enterprise,
        created_at::timestamp                       as created_at,
        updated_at::timestamp                       as updated_at
    from deduped
    where rn = 1
)

select * from final