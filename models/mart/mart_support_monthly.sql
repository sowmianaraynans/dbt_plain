-- mart_support_monthly.sql
-- ============================================================
-- SUPPORT OPERATIONS — MONTHLY ROLLUP
-- ============================================================
-- Leadership view of support health by month and tier.
-- Aggregates fact_thread_measures (daily × channel × priority × tier)
-- up to monthly × tier grain for BI consumption.
--
-- All averages computed as weighted sum / count — never avg(avg).
-- p90 / median omitted: non-additive, cannot be reconstructed
-- by summing daily percentile rows.
--
-- Grain: one row per (report_month, company_tier)
-- ============================================================

with daily as (
    select * from {{ ref('fact_thread_measures') }}
),

monthly as (
    select
        date_trunc('month', created_date)::date                             as report_month,
        company_tier,

        -- ── Volume ────────────────────────────────────────────────────
        sum(total_threads)                                                  as thread_volume,
        sum(resolved_threads)                                               as threads_resolved,
        sum(open_threads)                                                   as threads_open_eod,
        sum(escalated_threads)                                              as escalations,
        sum(high_priority_threads)                                          as high_priority_threads,

        -- ── Resolution ────────────────────────────────────────────────
        round(
            100.0 * sum(resolved_threads) / nullif(sum(total_threads), 0), 1
        )                                                                   as resolution_rate_pct,

        -- ── First response time ───────────────────────────────────────
        -- Weighted avg: SUM(mins) / COUNT(responses). Correct across tiers.
        round(
            sum(sum_frt_mins) / nullif(sum(frt_response_count), 0), 1
        )                                                                   as avg_frt_mins,
        sum(frt_response_count)                                             as frt_threads_with_response,

        -- ── Time to resolution ────────────────────────────────────────
        round(
            sum(sum_ttr_mins) / nullif(sum(ttr_resolved_count), 0), 1
        )                                                                   as avg_ttr_mins,
        sum(ttr_resolved_count)                                             as ttr_threads_resolved,

        -- ── Engagement ────────────────────────────────────────────────
        round(
            sum(sum_messages) / nullif(sum(total_threads), 0), 1
        )                                                                   as avg_messages_per_thread

    from daily
    group by 1, 2
)

select * from monthly
order by report_month desc, company_tier
