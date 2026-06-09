-- fact_agent_daily.sql
-- ============================================================
-- AGENT PERFORMANCE — TIME SERIES
-- ============================================================
-- Daily additive measures per agent for trend analysis.
--
-- ADDITIVE COLUMNS (sum freely across any dimension or time window):
--   threads_assigned, threads_resolved, threads_escalated,
--   high_priority_threads, frt_response_count, sum_frt_mins,
--   ttr_resolved_count, sum_ttr_mins, sla_breaches, channel counts
--
-- NON-ADDITIVE COLUMNS (daily-grain approximations — DO NOT avg across days):
--   p90_frt_mins, p90_ttr_mins, median_frt_mins, median_ttr_mins
--   These are percentile estimates for a single day. Averaging them
--   across multiple days does not produce a correct overall percentile.
--   Use them for single-day comparisons or reference only.
--
-- COMPUTING AVERAGES in the metric layer:
--   avg_frt_mins  = SUM(sum_frt_mins)  / NULLIF(SUM(frt_response_count), 0)
--   avg_ttr_mins  = SUM(sum_ttr_mins)  / NULLIF(SUM(ttr_resolved_count), 0)
--   resolution_rate = SUM(threads_resolved) / NULLIF(SUM(threads_assigned), 0)
--   This is correct at any grain: agent, week, month, company, team.
--
-- ROLLING COLUMNS store sums — not averages of averages:
--   rolling_7d_avg_frt_mins = rolling_7d_sum_frt_mins
--                             / NULLIF(rolling_7d_frt_response_count, 0)
--
-- Grain: one row per (activity_date, agent_id)
-- ============================================================

with threads as (
    select * from {{ ref('stg_threads') }}
),

breaches as (
    select * from {{ ref('stg_sla_breaches') }}
),

daily_threads as (
    select
        date_trunc('day', created_at)::date                             as activity_date,
        assigned_agent_id,
        assigned_agent_name,

        -- ── Additive volume ──────────────────────────────────────
        count(*)                                                        as threads_assigned,
        countif(is_resolved)                                            as threads_resolved,
        countif(not is_resolved)                                        as threads_open_eod,
        countif(is_escalated)                                           as threads_escalated,
        countif(is_high_priority)                                       as high_priority_threads,
        -- currently open AND high priority (evaluated at model-run time, not historical EOD)
        -- SUM across all dates = current open high-priority queue per agent
        countif(is_high_priority and not is_resolved)                   as high_priority_open_eod,

        -- ── FRT: store sum + count for correct upstream aggregation
        count(first_response_time_mins)                                 as frt_response_count,
        round(sum(first_response_time_mins), 1)                         as sum_frt_mins,

        -- ── TTR: same pattern — sum + count only for resolved threads
        countif(is_resolved and resolution_time_mins is not null)       as ttr_resolved_count,
        round(sum(case when is_resolved
            then resolution_time_mins else null end), 1)                as sum_ttr_mins,

        -- ── Daily-grain percentile approximations ────────────────
        -- Use for single-day comparisons or trend direction only.
        -- Do NOT average these across multiple days — it is incorrect.
        round(median(first_response_time_mins), 1)                      as median_frt_mins,
        round(percentile_cont(0.90) within group
            (order by first_response_time_mins), 1)                     as p90_frt_mins,
        round(median(resolution_time_mins), 1)                          as median_ttr_mins,
        round(percentile_cont(0.90) within group
            (order by resolution_time_mins), 1)                         as p90_ttr_mins,

        -- ── Channel mix (additive) ────────────────────────────────
        countif(channel = 'slack')                                      as slack_threads,
        countif(channel = 'email')                                      as email_threads,
        countif(channel = 'chat')                                       as chat_threads,
        countif(channel = 'api')                                        as api_threads

    from threads
    where assigned_agent_id is not null
    group by 1, 2, 3
),

daily_breaches as (
    select
        date_trunc('day', breached_at)::date                            as activity_date,
        assigned_agent_id,
        count(*)                                                        as sla_breaches,
        count(distinct company_id)                                      as companies_breached
    from breaches
    group by 1, 2
),

final as (
    select
        dt.activity_date,
        date_trunc('week',  dt.activity_date)::date                     as activity_week,
        date_trunc('month', dt.activity_date)::date                     as activity_month,

        dt.assigned_agent_id                                            as agent_id,
        dt.assigned_agent_name                                          as agent_name,

        -- ── Daily volume ──────────────────────────────────────────
        dt.threads_assigned,
        dt.threads_resolved,
        dt.threads_open_eod,
        dt.threads_escalated,
        dt.high_priority_threads,
        dt.high_priority_open_eod,

        -- ── Daily speed (additive components) ────────────────────
        -- Use these to compute avg in any BI layer or metric query:
        --   avg_frt = SUM(sum_frt_mins) / NULLIF(SUM(frt_response_count), 0)
        dt.frt_response_count,
        dt.sum_frt_mins,
        dt.ttr_resolved_count,
        dt.sum_ttr_mins,

        -- ── Daily-grain percentile approximations ────────────────
        dt.median_frt_mins,
        dt.p90_frt_mins,
        dt.median_ttr_mins,
        dt.p90_ttr_mins,

        -- ── Channel mix ───────────────────────────────────────────
        dt.slack_threads,
        dt.email_threads,
        dt.chat_threads,
        dt.api_threads,

        -- ── SLA (additive) ────────────────────────────────────────
        coalesce(db.sla_breaches, 0)                                    as sla_breaches,
        coalesce(db.companies_breached, 0)                              as companies_breached,

        -- ── Rolling 7-day sums — divide in metric layer ──────────
        -- Correct: sum the components, then divide once.
        -- Wrong:   avg(daily_avg_frt) — volumes differ per day.
        sum(dt.threads_assigned) over w7                                as rolling_7d_threads_assigned,
        sum(dt.threads_resolved) over w7                                as rolling_7d_threads_resolved,
        sum(dt.frt_response_count) over w7                              as rolling_7d_frt_response_count,
        sum(dt.sum_frt_mins) over w7                                    as rolling_7d_sum_frt_mins,
        sum(dt.ttr_resolved_count) over w7                              as rolling_7d_ttr_resolved_count,
        sum(dt.sum_ttr_mins) over w7                                    as rolling_7d_sum_ttr_mins,
        sum(coalesce(db.sla_breaches, 0)) over w7                       as rolling_7d_sla_breaches,

        -- ── Convenience: rolling 7-day avg (pre-divided) ─────────
        -- Ready to display in dashboards, but cannot be re-aggregated.
        -- For aggregating across agents use the rolling sum columns above.
        round(
            sum(dt.sum_frt_mins) over w7
            / nullif(sum(dt.frt_response_count) over w7, 0),
        1)                                                              as rolling_7d_avg_frt_mins,

        round(
            sum(dt.sum_ttr_mins) over w7
            / nullif(sum(dt.ttr_resolved_count) over w7, 0),
        1)                                                              as rolling_7d_avg_ttr_mins

    from daily_threads dt
    left join daily_breaches db
        on  dt.assigned_agent_id = db.assigned_agent_id
        and dt.activity_date     = db.activity_date

    window w7 as (
        partition by dt.assigned_agent_id
        order by dt.activity_date
        rows between 6 preceding and current row
    )
)

select * from final
order by activity_date desc, agent_id
