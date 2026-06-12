-- mart_sla_monthly.sql
-- ============================================================
-- SLA HEALTH — MONTHLY BY TIER
-- ============================================================
-- Leadership and CSM view of SLA compliance by month and tier.
-- Aggregates fact_sla_performance (company-month-sla_type grain)
-- to monthly × tier grain.
--
-- SELECTION BIAS NOTE:
--   fact_sla_performance only contains company-months that had at
--   least one breach. avg_compliance_pct here is the average among
--   breaching company-months only — not fleet-wide compliance.
--   Interpretation: "of the companies that had a breach, how compliant
--   were they on average?" — not "what % of all threads met SLA?"
--   For true fleet-wide compliance, join to a full company-month spine.
--
-- critical_accounts / warning_accounts are distinct company counts —
-- a company breaching both FRT and TTR in the same month counts once.
--
-- Grain: one row per (report_month, company_tier)
-- ============================================================

with sla as (
    select * from {{ ref('fact_sla_performance') }}
),

monthly as (
    select
        breach_month                                                    as report_month,
        company_tier,

        -- ── Breach summary ────────────────────────────────────────────
        count(distinct company_id)                                      as companies_with_breaches,
        sum(breach_count)                                               as total_breach_events,
        sum(threads_breached)                                           as threads_breached,

        -- ── Risk concentration ────────────────────────────────────────
        -- Distinct companies — a company with both FRT and TTR breaches counts once
        count(distinct case when risk_flag = 'critical' then company_id end) as critical_accounts,
        count(distinct case when risk_flag = 'warning'  then company_id end) as warning_accounts,
        count(distinct case when risk_flag = 'ok'       then company_id end) as ok_accounts,

        -- ── Compliance distribution among breaching companies ─────────
        round(avg(sla_compliance_pct), 1)                               as avg_compliance_pct,
        round(min(sla_compliance_pct), 1)                               as worst_compliance_pct,

        -- ── Severity ─────────────────────────────────────────────────
        round(avg(avg_breach_by_mins), 1)                               as avg_breach_severity_mins,
        round(max(worst_breach_mins), 1)                                as worst_single_breach_mins

    from sla
    group by 1, 2
)

select * from monthly
order by report_month desc, company_tier
