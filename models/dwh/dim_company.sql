-- dim_company.sql
-- ============================================================
-- COMPANY DIMENSION
-- ============================================================
-- Account-level rollup — the primary view a Plain CSM opens
-- to assess the health of an account and prioritise outreach.
--
-- Customer health breakdown sourced from dim_customer so that
-- health_status logic is defined once and flows here correctly.
--
-- Grain: one row per company_id.
-- ============================================================

with companies as (
    select * from {{ ref('stg_companies') }}
),

-- Source from dim_customer, not stg_customers, so health_status
-- is available and consistent with what individual teams see.
customer_health as (
    select
        company_id,

        -- Volume
        count(*)                                            as total_customers,
        countif(is_active)                                  as active_customers,
        countif(is_churned)                                 as churned_customers,

        -- Health distribution — the CSM view
        countif(health_status = 'healthy')                  as healthy_customers,
        countif(health_status = 'new')                      as new_customers,
        countif(health_status = 'idle')                     as idle_customers,
        countif(health_status = 'needs_attention')          as needs_attention_customers,
        countif(health_status = 'at_risk')                  as at_risk_customers,

        -- Support signal rollup
        sum(total_threads)                                  as total_threads_all_customers,
        sum(open_threads)                                   as open_threads_all_customers,
        round(avg(avg_first_response_time_mins), 1)         as avg_frt_mins,
        round(avg(p90_first_response_time_mins), 1)         as p90_frt_mins,
        round(avg(avg_resolution_time_mins), 1)             as avg_ttr_mins,
        round(avg(p90_resolution_time_mins), 1)             as p90_ttr_mins

    from {{ ref('dim_customer') }}
    group by 1
),

tenant_counts as (
    select
        company_id,
        count(distinct tenant_id)                           as tenant_count
    from {{ ref('stg_tenants') }}
    group by 1
),

thread_counts as (
    select
        company_id,
        count(*)                                            as total_threads,
        countif(not is_resolved)                            as open_threads,
        countif(is_high_priority)                           as high_priority_threads
    from {{ ref('stg_threads') }}
    group by 1
),

sla_counts as (
    select
        company_id,
        count(*)                                            as sla_breach_count
    from {{ ref('stg_sla_breaches') }}
    group by 1
)

select
    -- ── Company attributes ────────────────────────────────────
    c.company_id,
    c.company_name,
    c.domain_name,
    c.company_tier,
    c.region,
    c.is_active,
    c.is_enterprise,
    c.is_paying,
    c.mrr_usd,
    c.created_at,
    c.updated_at,

    -- ── Customer counts ───────────────────────────────────────
    coalesce(ch.total_customers, 0)                         as total_customers,
    coalesce(ch.active_customers, 0)                        as active_customers,
    coalesce(ch.churned_customers, 0)                       as churned_customers,

    round(
        100.0 * coalesce(ch.churned_customers, 0)
            / nullif(coalesce(ch.total_customers, 0), 0),
        1
    )                                                       as customer_churn_rate_pct,

    -- ── Health distribution (CSM account view) ────────────────
    -- How many of this company's users are in each health state?
    -- A CSM sorting by at_risk_customers + needs_attention_customers
    -- gets their intervention list for the week.
    coalesce(ch.healthy_customers, 0)                       as healthy_customers,
    coalesce(ch.new_customers, 0)                           as new_customers,
    coalesce(ch.idle_customers, 0)                          as idle_customers,
    coalesce(ch.needs_attention_customers, 0)               as needs_attention_customers,
    coalesce(ch.at_risk_customers, 0)                       as at_risk_customers,

    -- % of users needing attention — quick account risk score for CSMs
    round(
        100.0 * (coalesce(ch.at_risk_customers, 0) + coalesce(ch.needs_attention_customers, 0))
            / nullif(coalesce(ch.total_customers, 0), 0),
        1
    )                                                       as pct_customers_needing_attention,

    -- ── Support speed (avg across all customers in account) ───
    ch.avg_frt_mins,
    ch.p90_frt_mins,
    ch.avg_ttr_mins,
    ch.p90_ttr_mins,

    -- ── Tenant and thread counts ──────────────────────────────
    coalesce(tc.tenant_count, 0)                            as tenant_count,
    coalesce(tc2.total_threads, 0)                          as total_threads,
    coalesce(tc2.open_threads, 0)                           as open_threads,
    coalesce(tc2.high_priority_threads, 0)                  as high_priority_threads,
    coalesce(sc.sla_breach_count, 0)                        as sla_breach_count

from companies c
left join customer_health ch    on c.company_id = ch.company_id
left join tenant_counts tc      on c.company_id = tc.company_id
left join thread_counts tc2     on c.company_id = tc2.company_id
left join sla_counts sc         on c.company_id = sc.company_id
