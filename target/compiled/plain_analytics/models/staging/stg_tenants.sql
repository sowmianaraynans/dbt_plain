-- stg_tenants.sql
-- Cleaned tenant records. Tenants are logical workspaces within a company
-- (e.g. production vs staging, or a sub-product). Used in the customer spine
-- to add workspace-level context to each customer.

with source as (
    select * from "plain_analytics"."main_raw"."raw_tenants"
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
        id                              as tenant_id,
        external_id,
        company_id,
        name                            as tenant_name,
        tier                            as company_tier,
        created_at::timestamp           as created_at,
        updated_at::timestamp           as updated_at
    from deduped
    where rn = 1
)

select * from final