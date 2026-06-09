-- fact_mrr_monthly.sql
-- ============================================================
-- MRR TIME-SERIES
-- ============================================================
-- Monthly MRR movements by tier — the model leadership uses to
-- answer "how is revenue trending?" not just "what is ARR today?"
--
-- Three MRR buckets per month:
--   active_mrr  — MRR from all companies active this month
--   new_mrr     — MRR from companies that became active this month
--                 (first month ever, or reactivated from churned)
--   churned_mrr — MRR lost from companies that went inactive this month
--
-- net_new_mrr = new_mrr - churned_mrr
--   Positive → revenue growing
--   Negative → more being lost than gained
--
-- Expansion MRR (mrr_usd increases for existing accounts) is always 0
-- with static seed data. In production with Stripe, add:
-- expansion_mrr and contraction_mrr for the full waterfall.
--
-- Powered by stg_company_snapshots (monthly history).
-- Production path: run `dbt snapshot` on a schedule so that
-- snapshots/company_snapshot.sql builds this history from live data.
--
-- SELF-SERVE QUERY GUIDE:
--   Current ARR by tier (snapshot answer from latest month):
--     SELECT company_tier, active_mrr * 12 as arr_usd, active_companies
--     FROM fact_mrr_monthly
--     WHERE snapshot_month = (SELECT MAX(snapshot_month) FROM fact_mrr_monthly)
--     ORDER BY arr_usd DESC
--
--   MRR trend over time:
--     SELECT snapshot_month, company_tier,
--            active_mrr, new_mrr, churned_mrr, net_new_mrr
--     FROM fact_mrr_monthly
--     ORDER BY snapshot_month DESC, active_mrr DESC
--
--   Is growth accelerating? (total net new MRR by month):
--     SELECT snapshot_month, SUM(net_new_mrr) as total_net_new_mrr
--     FROM fact_mrr_monthly
--     GROUP BY 1 ORDER BY 1
--
-- Grain: one row per (snapshot_month, company_tier)
-- Free tier excluded — no MRR.
-- ============================================================

with monthly as (
    select
        snapshot_month,
        company_id,
        company_tier,
        is_active,
        mrr_usd,

        -- Previous month's state per company — detects new and churned events
        lag(is_active) over (
            partition by company_id
            order by snapshot_month
        )                                               as prev_is_active,

        lag(mrr_usd) over (
            partition by company_id
            order by snapshot_month
        )                                               as prev_mrr_usd

    from {{ ref('stg_company_snapshots') }}
    where company_tier != 'free'
),

final as (
    select
        snapshot_month,
        company_tier,

        -- ── Active base ───────────────────────────────────────────
        count(case when is_active then 1 end)                           as active_companies,
        sum(case when is_active then mrr_usd else 0 end)                as active_mrr,
        sum(case when is_active then mrr_usd else 0 end) * 12           as active_arr,

        -- ── New MRR ───────────────────────────────────────────────
        -- Active this month AND was inactive or not yet present last month
        count(case
            when is_active and coalesce(prev_is_active, false) = false
            then 1 end)                                                 as new_companies,

        sum(case
            when is_active and coalesce(prev_is_active, false) = false
            then mrr_usd else 0 end)                                    as new_mrr,

        -- ── Churned MRR ───────────────────────────────────────────
        -- Was active last month AND is inactive this month
        -- Use prev_mrr_usd because current mrr_usd is 0 once churned
        count(case
            when not is_active and coalesce(prev_is_active, false) = true
            then 1 end)                                                 as churned_companies,

        sum(case
            when not is_active and coalesce(prev_is_active, false) = true
            then coalesce(prev_mrr_usd, 0) else 0 end)                 as churned_mrr,

        -- ── Net new MRR ───────────────────────────────────────────
        sum(case
            when is_active and coalesce(prev_is_active, false) = false
            then mrr_usd else 0 end)
        -
        sum(case
            when not is_active and coalesce(prev_is_active, false) = true
            then coalesce(prev_mrr_usd, 0) else 0 end)                 as net_new_mrr

    from monthly
    group by 1, 2
)

select * from final
order by snapshot_month desc, active_mrr desc
