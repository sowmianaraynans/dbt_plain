-- fact_thread_measures.sql
-- ============================================================
-- THREAD MEASURES
-- ============================================================
-- Daily operational metrics for support leaders.
-- Answers: how fast are we resolving? where are bottlenecks?
--
-- ADDITIVE COLUMNS (sum freely across any combination of dimensions):
--   total_threads, resolved_threads, open_threads, escalated_threads,
--   high_priority_threads, frt_response_count, sum_frt_mins,
--   ttr_resolved_count, sum_ttr_mins, sum_messages
--
-- NON-ADDITIVE COLUMNS (daily-grain approximations — DO NOT avg across rows):
--   p90_frt_mins, p90_ttr_mins, median_frt_mins, median_ttr_mins
--
-- COMPUTING DERIVED METRICS in any BI layer or metric query:
--   avg_frt_mins      = SUM(sum_frt_mins)    / NULLIF(SUM(frt_response_count), 0)
--   avg_ttr_mins      = SUM(sum_ttr_mins)    / NULLIF(SUM(ttr_resolved_count), 0)
--   resolution_rate   = SUM(resolved_threads) / NULLIF(SUM(total_threads), 0)
--   avg_msgs_per_thread = SUM(sum_messages)  / NULLIF(SUM(total_threads), 0)
--
-- Date truncations beyond created_date (week, month, quarter, year)
-- are intentionally omitted — MetricFlow time spine and BI tools
-- derive all granularities from a single date column.
--
-- Grain: one row per (created_date, channel, priority, company_tier)
-- ============================================================

with threads as (
    select * from {{ ref('stg_threads') }}
),

daily as (
    select
        date_trunc('day', created_at)::date                             as created_date,
        channel,
        priority,
        company_tier,

        -- ── Volume (additive) ─────────────────────────────────────
        count(*)                                                        as total_threads,
        countif(is_resolved)                                            as resolved_threads,
        -- open_threads: created on this date and not yet resolved at model-run time.
        -- Rows for older dates decrease as threads resolve — this table is not immutable.
        countif(not is_resolved)                                        as open_threads,
        countif(is_escalated)                                           as escalated_threads,
        countif(is_high_priority)                                       as high_priority_threads,

        -- ── FRT: additive primitives for correct aggregation ──────
        count(first_response_time_mins)                                 as frt_response_count,
        round(sum(first_response_time_mins), 1)                         as sum_frt_mins,

        -- ── TTR: additive primitives ──────────────────────────────
        countif(is_resolved and resolution_time_mins is not null)       as ttr_resolved_count,
        round(sum(case when is_resolved
            then resolution_time_mins else null end), 1)                as sum_ttr_mins,

        -- ── Messages: additive sum ─────────────────────────────────
        sum(message_count)                                              as sum_messages,

        -- ── Daily-grain percentile approximations ─────────────────
        -- Use for single-row comparisons or trend direction only.
        -- Averaging these across rows does not produce a correct overall percentile.
        round(median(first_response_time_mins), 1)                      as median_frt_mins,
        round(percentile_cont(0.90) within group
            (order by first_response_time_mins), 1)                     as p90_frt_mins,
        round(median(resolution_time_mins), 1)                          as median_ttr_mins,
        round(percentile_cont(0.90) within group
            (order by resolution_time_mins), 1)                         as p90_ttr_mins

    from threads
    group by 1, 2, 3, 4
)

select * from daily
order by created_date desc, total_threads desc
