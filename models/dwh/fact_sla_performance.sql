-- fact_sla_performance.sql
-- ============================================================
-- SLA PERFORMANCE
-- ============================================================
-- Tracks SLA health by tier and company — the table a CSM or
-- support leader opens when they ask "are we meeting our commitments?"
--
-- Grain: one row per (breach_month, company_tier, company_id)
-- ============================================================

with breaches as (
    select * from {{ ref('stg_sla_breaches') }}
),

threads as (
    select
        company_id,
        date_trunc('month', created_at)     as thread_month,
        count(*)                            as total_threads
    from {{ ref('stg_threads') }}
    where company_tier != 'free'            -- free tier has no SLA
    group by 1, 2
),

breach_agg as (
    select
        breach_month,
        company_id,
        company_tier,
        sla_type,

        count(*)                                        as breach_count,
        round(avg(breach_by_minutes), 1)                as avg_breach_by_mins,
        round(max(breach_by_minutes), 1)                as worst_breach_mins,
        count(distinct thread_id)                       as threads_breached,
        count(distinct assigned_agent_id)               as agents_involved

    from breaches
    group by 1, 2, 3, 4
),

final as (
    select
        ba.breach_month,
        ba.company_id,
        ba.company_tier,
        ba.sla_type,
        ba.breach_count,
        ba.threads_breached,
        ba.avg_breach_by_mins,
        ba.worst_breach_mins,
        ba.agents_involved,

        -- SLA compliance rate (for this company-month)
        t.total_threads,
        round(
            100.0 * (1 - ba.threads_breached::float / nullif(t.total_threads, 0)),
            1
        )                                               as sla_compliance_pct,

        -- Risk flag
        case
            when ba.company_tier = 'enterprise' and ba.breach_count > 1   then 'critical'
            when ba.company_tier = 'enterprise' and ba.breach_count = 1   then 'warning'
            when ba.company_tier = 'pro'        and ba.breach_count > 3   then 'warning'
            else 'ok'
        end                                             as risk_flag

    from breach_agg ba
    left join threads t
        on  ba.company_id   = t.company_id
        and ba.breach_month = t.thread_month
)

select * from final
order by breach_month desc, risk_flag, company_tier
