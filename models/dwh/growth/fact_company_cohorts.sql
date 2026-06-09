-- fact_company_cohorts.sql
-- ============================================================
-- COMPANY COHORT RETENTION — PERIOD BY PERIOD
-- ============================================================
-- True cohort development over time: how does each acquisition
-- cohort's logo and revenue retention evolve month by month?
--
-- Powered by stg_company_snapshots (monthly status history),
-- which simulates the output of snapshots/company_snapshot.sql.
-- In production: run `dbt snapshot` on a schedule; the snapshot
-- builds this history automatically from live source changes.
--
-- SELF-SERVE QUERY GUIDE:
--   Cohort retention triangle (month 0 = 100%, watch the decay):
--     SELECT cohort_month, months_into_cohort, company_tier,
--            logo_retention_pct, mrr_retention_pct
--     FROM fact_company_cohorts
--     ORDER BY cohort_month, months_into_cohort
--
--   Which cohort had the sharpest early drop-off (month 1 vs month 3)?:
--     SELECT cohort_month, company_tier,
--            MAX(CASE WHEN months_into_cohort = 1 THEN logo_retention_pct END) as m1_retention,
--            MAX(CASE WHEN months_into_cohort = 3 THEN logo_retention_pct END) as m3_retention
--     FROM fact_company_cohorts
--     GROUP BY 1, 2 HAVING m1_retention IS NOT NULL
--     ORDER BY m1_retention ASC
--
--   MRR retained for cohorts older than 6 months:
--     SELECT cohort_month, company_tier,
--            retained_mrr_usd, churned_mrr_usd, mrr_retention_pct
--     FROM fact_company_cohorts
--     WHERE months_into_cohort = 6
--     ORDER BY mrr_retention_pct ASC
--
-- Grain: one row per (cohort_month, period_month, company_tier)
-- Free tier excluded — no MRR, not meaningful for growth analysis.
-- ============================================================

with company_cohorts as (
    select
        company_id,
        date_trunc('month', created_at)::date   as cohort_month,
        company_tier
    from {{ ref('stg_companies') }}
    where company_tier != 'free'
),

snapshots as (
    select
        company_id,
        snapshot_month,
        is_active,
        mrr_usd
    from {{ ref('stg_company_snapshots') }}
),

cohort_periods as (
    select
        cc.cohort_month,
        s.snapshot_month                                                    as period_month,
        cc.company_tier,
        datediff('month', cc.cohort_month, s.snapshot_month)               as months_into_cohort,

        -- ── Volume ────────────────────────────────────────────────
        count(distinct cc.company_id)                                       as cohort_size,
        count(distinct case when s.is_active     then cc.company_id end)    as active_companies,
        count(distinct case when not s.is_active then cc.company_id end)    as churned_companies,

        -- ── Revenue ───────────────────────────────────────────────
        -- mrr_usd is static in seeds — in production, mrr may expand/contract.
        -- Use mrr_retention_pct to identify whether larger or smaller
        -- accounts are churning (divergence from logo_retention_pct is signal).
        sum(s.mrr_usd)                                                      as period_mrr_usd,
        sum(case when s.is_active     then s.mrr_usd else 0 end)            as retained_mrr_usd,
        sum(case when not s.is_active then s.mrr_usd else 0 end)            as churned_mrr_usd,

        -- ── Rates ─────────────────────────────────────────────────
        round(
            100.0 * count(distinct case when s.is_active then cc.company_id end)
                  / nullif(count(distinct cc.company_id), 0), 1
        )                                                                   as logo_retention_pct,

        round(
            100.0 * count(distinct case when not s.is_active then cc.company_id end)
                  / nullif(count(distinct cc.company_id), 0), 1
        )                                                                   as logo_churn_pct,

        round(
            100.0 * sum(case when s.is_active then s.mrr_usd else 0 end)
                  / nullif(sum(s.mrr_usd), 0), 1
        )                                                                   as mrr_retention_pct,

        round(
            100.0 * sum(case when not s.is_active then s.mrr_usd else 0 end)
                  / nullif(sum(s.mrr_usd), 0), 1
        )                                                                   as mrr_churn_rate_pct

    from company_cohorts cc
    inner join snapshots s
        on  cc.company_id    = s.company_id
        and s.snapshot_month >= cc.cohort_month

    group by 1, 2, 3, 4
)

select * from cohort_periods
order by cohort_month, months_into_cohort, company_tier
