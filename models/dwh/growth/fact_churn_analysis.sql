-- fact_churn_analysis.sql
-- ============================================================
-- CHURN ANALYSIS
-- ============================================================
-- Point-in-time churn and retention rates by cohort and tier.
-- Also surfaces revenue at risk from churned and idle customers.
--
-- Limitation: customer status is a snapshot — we cannot determine
-- exactly when churn occurred without a status history table.
-- In production, a CDC-derived status_history table enables true
-- monthly churn rate and reactivation tracking.
--
-- Grain: one row per (cohort_month, company_tier)
-- ============================================================

with customers as (
    select * from {{ ref('stg_customers') }}
),

companies as (
    select company_id, mrr_usd
    from {{ ref('stg_companies') }}
),

churn as (
    select
        date_trunc('month', c.created_at)::date                         as cohort_month,
        c.company_tier,

        -- Volume
        count(*)                                                        as total_customers,
        countif(c.is_churned)                                           as churned_customers,
        countif(c.is_active)                                            as retained_customers,
        countif(c.status = 'idle')                                      as idle_customers,

        -- Rates
        round(
            100.0 * countif(c.is_churned) / nullif(count(*), 0), 1
        )                                                               as churn_rate_pct,

        round(
            100.0 * countif(c.is_active) / nullif(count(*), 0), 1
        )                                                               as retention_rate_pct,

        -- Revenue impact (company MRR proxied to customer level)
        -- Directional signal only — true churn revenue needs Stripe
        sum(case when c.is_churned then co.mrr_usd else 0 end)         as churned_mrr_usd,
        sum(case when c.status = 'idle' then co.mrr_usd else 0 end)    as at_risk_mrr_usd,
        sum(case when c.is_active then co.mrr_usd else 0 end)          as retained_mrr_usd

    from customers c
    left join companies co using (company_id)
    group by 1, 2
)

select * from churn
order by cohort_month desc, churn_rate_pct desc
