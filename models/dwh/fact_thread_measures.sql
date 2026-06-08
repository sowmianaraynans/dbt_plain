-- fact_thread_measures.sql
-- ============================================================
-- THREAD MEASURES
-- ============================================================
-- Daily operational metrics for support leaders.
-- Answers: how fast are we resolving? where are bottlenecks?
--
-- Grain: one row per (created_date, channel, priority, company_tier)
-- ============================================================

with threads as (
    select * from {{ ref('stg_threads') }}
),

daily as (
    select
        date_trunc('day', created_at)::date         as created_date,
        date_trunc('week', date_trunc('day', created_at))  as created_week,
        date_trunc('month', date_trunc('day', created_at)) as created_month,
        date_trunc('quarter', date_trunc('day', created_at)) as created_quarter,
        date_part('year', date_trunc('day', created_at))::int as created_year,
        channel,
        priority,
        company_tier,

        -- Volume
        count(*)                                        as total_threads,
        countif(is_resolved)                            as resolved_threads,
        countif(not is_resolved)                        as open_threads,
        countif(is_escalated)                           as escalated_threads,
        countif(is_high_priority)                       as high_priority_threads,

        -- Speed (first response)
        round(avg(first_response_time_mins), 1)         as avg_frt_mins,
        round(median(first_response_time_mins), 1)      as median_frt_mins,
        round(percentile_cont(0.90) within group
            (order by first_response_time_mins), 1)     as p90_frt_mins,

        -- Speed (resolution)
        round(avg(resolution_time_mins), 1)             as avg_ttr_mins,
        round(median(resolution_time_mins), 1)          as median_ttr_mins,
        round(percentile_cont(0.90) within group
            (order by resolution_time_mins), 1)         as p90_ttr_mins,

        -- Throughput
        round(avg(message_count), 1)                    as avg_messages_per_thread,

        -- Resolution rate
        round(
            100.0 * countif(is_resolved) / nullif(count(*), 0),
            1
        )                                               as resolution_rate_pct

    from threads
    group by 1, 2, 3, 4, 5, 6, 7, 8
)

select * from daily
order by created_date desc, total_threads desc
