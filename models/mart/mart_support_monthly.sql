-- mart_support_monthly.sql
-- ============================================================
-- SUPPORT OPERATIONS — MONTHLY BY COMPANY
-- ============================================================
-- Leadership and CSM view of support health.
-- Sources from fact_threads (thread grain) — all company dimensions
-- are already joined there, so the mart inherits them cleanly.
--
-- Grain: one row per (report_month, company_id)
-- Metabase users can filter by company_name, region, or company_tier
-- and group/pivot freely without any join configuration.
--
-- Weighted averages computed as SUM/COUNT — never avg(avg).
-- ============================================================

with threads as (
    select * from {{ ref('fact_threads') }}
),

monthly as (
    select
        date_trunc('month', created_date)::date                         as report_month,

        -- ── Company dimensions ────────────────────────────────────
        company_id,
        company_name,
        company_tier,
        region,

        -- ── Volume ────────────────────────────────────────────────
        count(*)                                                        as thread_volume,
        countif(is_resolved)                                            as threads_resolved,
        countif(not is_resolved)                                        as threads_open_eod,
        countif(is_escalated)                                           as escalations,
        countif(is_high_priority)                                       as high_priority_threads,

        -- ── Resolution ────────────────────────────────────────────
        round(
            100.0 * countif(is_resolved) / nullif(count(*), 0), 1
        )                                                               as resolution_rate_pct,

        -- ── First response time (weighted avg) ────────────────────
        count(first_response_time_mins)                                 as frt_threads_with_response,
        round(
            sum(first_response_time_mins)
                / nullif(count(first_response_time_mins), 0), 1
        )                                                               as avg_frt_mins,

        -- ── Time to resolution (weighted avg) ─────────────────────
        countif(is_resolved and resolution_time_mins is not null)       as ttr_threads_resolved,
        round(
            sum(case when is_resolved then resolution_time_mins end)
                / nullif(countif(is_resolved and resolution_time_mins is not null), 0), 1
        )                                                               as avg_ttr_mins,

        -- ── Engagement ────────────────────────────────────────────
        round(
            sum(message_count) / nullif(count(*), 0), 1
        )                                                               as avg_messages_per_thread

    from threads
    group by 1, 2, 3, 4, 5
)

select * from monthly
order by report_month desc, thread_volume desc
