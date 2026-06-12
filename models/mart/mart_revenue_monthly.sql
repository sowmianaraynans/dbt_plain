-- mart_revenue_monthly.sql
-- ============================================================
-- REVENUE + LOGO MOVEMENT — MONTHLY
-- ============================================================
-- Leadership view of MRR waterfall and logo counts by month and tier.
-- Extends fact_mrr_monthly with correctly-computed rates.
--
-- KEY CORRECTION vs MetricFlow logo_churn_rate metric:
--   Standard logo churn rate uses beginning-of-period (bop) company count.
--   bop = active_companies - new_companies + churned_companies
--   (because: end = bop + new - churned → bop = end - new + churned)
--   MetricFlow approximates with end-of-period; this mart uses bop.
--
-- ARPA (avg_mrr_per_company) uses end-of-period actives as denominator
-- because MRR is earned by the companies active at period end.
--
-- mrr_usd is a static seed field — directional only.
-- Replace with Stripe subscription events for billing-accurate MRR.
--
-- Grain: one row per (report_month, company_tier)
-- ============================================================

with base as (
    select * from {{ ref('fact_mrr_monthly') }}
),

final as (
    select
        snapshot_month                                                          as report_month,
        company_tier,

        -- ── Logo counts ───────────────────────────────────────────────────────
        active_companies                                                        as active_logos,
        new_companies                                                           as new_logos,
        churned_companies                                                       as churned_logos,

        -- Beginning-of-period logo count for rate calculations
        -- bop = end - new + churned (derived from: end = bop + new - churned)
        active_companies - new_companies + churned_companies                    as bop_logos,

        -- ── Logo rates (denominator = bop — the correct industry standard) ────
        round(
            100.0 * new_companies
                / nullif(active_companies - new_companies + churned_companies, 0), 1
        )                                                                       as new_logo_rate_pct,

        round(
            100.0 * churned_companies
                / nullif(active_companies - new_companies + churned_companies, 0), 1
        )                                                                       as logo_churn_rate_pct,

        -- ── MRR waterfall ─────────────────────────────────────────────────────
        active_mrr,
        active_arr,
        new_mrr,
        churned_mrr,
        net_new_mrr,

        -- ── ARPA ─────────────────────────────────────────────────────────────
        -- Uses end-of-period actives: MRR is earned by companies active at month end.
        round(active_mrr / nullif(active_companies, 0), 0)                     as avg_mrr_per_company

    from base
)

select * from final
order by report_month desc, active_mrr desc
