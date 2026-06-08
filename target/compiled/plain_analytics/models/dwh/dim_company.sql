-- dim_company.sql
-- ============================================================
-- COMPANY DIMENSION
-- ============================================================
-- Enriched account-level dimension with customer and support metrics.
-- Grain: one row per company_id.
-- ============================================================

with companies as (
    select * from "plain_analytics"."main_staging"."stg_companies"
),

customer_counts as (
    select
        company_id,
        count(*)                                        as total_customers,
        countif(is_active)                              as active_customers,
        countif(is_churned)                             as churned_customers
    from "plain_analytics"."main_staging"."stg_customers"
    group by 1
),

tenant_counts as (
    select
        company_id,
        count(distinct tenant_id)                       as tenant_count
    from "plain_analytics"."main_staging"."stg_tenants"
    group by 1
),

thread_counts as (
    select
        company_id,
        count(*)                                        as total_threads,
        countif(not is_resolved)                        as open_threads,
        countif(is_high_priority)                       as high_priority_threads
    from "plain_analytics"."main_staging"."stg_threads"
    group by 1
),

sla_counts as (
    select
        company_id,
        count(*)                                        as sla_breach_count
    from "plain_analytics"."main_staging"."stg_sla_breaches"
    group by 1
)

select
    c.*,
    coalesce(cc.total_customers, 0)                   as total_customers,
    coalesce(cc.active_customers, 0)                  as active_customers,
    coalesce(cc.churned_customers, 0)                 as churned_customers,

    -- Ratio matters more than raw count: 2/3 churned is critical, 2/100 is not.
    -- CSMs sort by this to prioritise at-risk accounts before the contract lapses.
    round(
        100.0 * coalesce(cc.churned_customers, 0)
            / nullif(coalesce(cc.total_customers, 0), 0),
        1
    )                                                 as customer_churn_rate_pct,

    coalesce(tc.tenant_count, 0)                      as tenant_count,
    coalesce(tc2.total_threads, 0)                    as total_threads,
    coalesce(tc2.open_threads, 0)                     as open_threads,
    coalesce(tc2.high_priority_threads, 0)            as high_priority_threads,
    coalesce(sc.sla_breach_count, 0)                  as sla_breach_count
from companies c
left join customer_counts cc using (company_id)
left join tenant_counts tc using (company_id)
left join thread_counts tc2 using (company_id)
left join sla_counts sc using (company_id)