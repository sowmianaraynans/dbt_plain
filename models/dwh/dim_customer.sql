-- dim_customer.sql
-- ============================================================
-- THE CUSTOMER DIMENSION
-- ============================================================
-- The single canonical entity that unifies every customer record
-- with their company (account), tenant, and tier context.
--
-- This is the table every downstream model joins on.
-- It answers the first question every team asks differently:
--   "How many active customers do we have?"
--
-- Without this spine, the answer varies by team.
-- With it, there is one answer.
--
-- Grain: one row per customer_id (unique)
-- ============================================================

with customers as (
    select * from {{ ref('stg_customers') }}
),

companies as (
    select * from {{ ref('stg_companies') }}
),

tenants as (
    select * from {{ ref('stg_tenants') }}
),

-- thread-level signals per customer
thread_signals as (
    select
        customer_id,
        count(*)                                                        as total_threads,
        countif(is_resolved)                                            as resolved_threads,
        countif(not is_resolved)                                        as open_threads,
        countif(is_escalated)                                           as escalated_threads,
        countif(is_high_priority)                                       as high_priority_threads,
        max(created_at)                                                 as last_thread_at,
        min(created_at)                                                 as first_thread_at,
        round(avg(first_response_time_mins), 1)                         as avg_first_response_time_mins,
        round(avg(resolution_time_mins), 1)                             as avg_resolution_time_mins,
        round(percentile_cont(0.90) within group
            (order by first_response_time_mins), 1)                     as p90_first_response_time_mins,
        round(percentile_cont(0.90) within group
            (order by resolution_time_mins), 1)                         as p90_resolution_time_mins
    from {{ ref('stg_threads') }}
    group by 1
),

final as (
    select
        -- ── Identity ──────────────────────────────────────────────
        c.customer_id,
        c.full_name                                         as customer_name,
        c.short_name,
        c.email,
        c.cohort_month,

        -- ── Company / Account ─────────────────────────────────────
        co.company_id,
        co.company_name,
        co.domain_name,
        co.company_tier,
        co.is_enterprise,
        co.is_paying,
        co.mrr_usd,
        co.region,
        co.is_active                                        as company_is_active,

        -- ── Tenant ────────────────────────────────────────────────
        t.tenant_id,
        t.tenant_name,

        -- ── Customer status ───────────────────────────────────────
        c.status                                            as customer_status,
        c.is_active,
        c.is_churned,

        -- ── Support signals ───────────────────────────────────────
        coalesce(ts.total_threads, 0)                       as total_threads,
        coalesce(ts.open_threads, 0)                        as open_threads,
        coalesce(ts.resolved_threads, 0)                    as resolved_threads,
        coalesce(ts.escalated_threads, 0)                   as escalated_threads,
        coalesce(ts.high_priority_threads, 0)               as high_priority_threads,
        ts.avg_first_response_time_mins,
        ts.avg_resolution_time_mins,
        ts.p90_first_response_time_mins,
        ts.p90_resolution_time_mins,
        ts.last_thread_at,
        ts.first_thread_at,

        -- ── Health signal (rule-based — replace with ML score when available) ──
        -- Evaluated top-down; first match wins.
        -- churned:          hard status from source — overrides everything.
        -- at_risk:          multiple escalations signal a relationship in trouble.
        -- needs_attention:  pile-up of open threads — support load is a burden.
        -- idle:             previously engaged but silent for 60+ days.
        --                   Requires total_threads > 0 — a customer who never
        --                   needed support is NOT idle; silence is a positive signal.
        -- healthy:          active customer, no red flags. Not needing support
        --                   is a valid healthy state — absence of tickets ≠ disengaged.
        -- new:              just onboarded, no meaningful signal yet.
        case
            when c.is_churned
                                                            then 'churned'
            when coalesce(ts.escalated_threads, 0) > 2
                                                            then 'at_risk'
            when coalesce(ts.open_threads, 0) > 5
                                                            then 'needs_attention'
            when coalesce(ts.total_threads, 0) > 0
                and ts.last_thread_at < current_timestamp - interval '60 days'
                                                            then 'idle'
            when c.is_active
                                                            then 'healthy'
            else 'new'
        end                                                 as health_status,

        -- ── Timestamps ────────────────────────────────────────────
        c.created_at,
        c.updated_at

    from customers c
    left join companies co      on c.company_id   = co.company_id
    left join tenants t         on c.tenant_id    = t.tenant_id
    left join thread_signals ts on c.customer_id  = ts.customer_id
)

select * from final
