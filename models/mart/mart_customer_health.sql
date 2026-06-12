-- mart_customer_health.sql
-- ============================================================
-- CUSTOMER HEALTH — CURRENT SNAPSHOT BY TIER
-- ============================================================
-- CSM and leadership view of customer health distribution.
-- Single row per company_tier showing head counts and risk signals.
--
-- SNAPSHOT: reflects current state (today), not historical.
-- All status and health_status columns come from dim_customer
-- which is refreshed on each dbt run.
--
-- Health status rules (see dim_customer for full logic):
--   churned         → is_churned = true
--   at_risk         → escalated_threads > 2
--   needs_attention → open_threads > 5
--   idle            → last_thread_at < 60 days ago (and has had threads)
--   healthy         → active, no red flags
--   new             → recently onboarded, no signal yet
--
-- Grain: one row per company_tier (snapshot)
-- ============================================================

with customers as (
    select * from {{ ref('dim_customer') }}
),

tier_summary as (
    select
        company_tier,

        -- ── Head counts ───────────────────────────────────────────────
        count(*)                                                            as total_customers,
        sum(case when is_active  then 1 else 0 end)                        as active_customers,
        sum(case when is_churned then 1 else 0 end)                        as churned_customers,

        -- ── Health distribution ───────────────────────────────────────
        sum(case when health_status = 'healthy'          then 1 else 0 end) as healthy,
        sum(case when health_status = 'idle'             then 1 else 0 end) as idle,
        sum(case when health_status = 'needs_attention'  then 1 else 0 end) as needs_attention,
        sum(case when health_status = 'at_risk'          then 1 else 0 end) as at_risk,
        sum(case when health_status = 'new'              then 1 else 0 end) as new_customers,
        sum(case when health_status = 'churned'          then 1 else 0 end) as health_churned,

        -- ── Risk rollup ───────────────────────────────────────────────
        sum(case when health_status in ('at_risk', 'needs_attention')
                 then 1 else 0 end)                                         as intervention_queue,

        -- ── Rates ─────────────────────────────────────────────────────
        round(
            100.0 * sum(case when is_churned then 1 else 0 end)
                / nullif(count(*), 0), 1
        )                                                                   as churn_pct,

        round(
            100.0 * sum(case when health_status in ('at_risk', 'needs_attention')
                             then 1 else 0 end)
                / nullif(sum(case when is_active then 1 else 0 end), 0), 1
        )                                                                   as at_risk_pct_of_active,

        round(
            100.0 * sum(case when health_status = 'healthy' then 1 else 0 end)
                / nullif(sum(case when is_active then 1 else 0 end), 0), 1
        )                                                                   as healthy_pct_of_active

    from customers
    group by 1
)

select * from tier_summary
order by
    case company_tier
        when 'enterprise' then 1
        when 'pro'        then 2
        when 'starter'    then 3
        else 4
    end
