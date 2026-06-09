-- dim_agent_workload.sql
-- ============================================================
-- AGENT WORKLOAD — CURRENT SNAPSHOT
-- ============================================================
-- Derived from fact_agent_daily by rolling up all history.
-- Grain: one row per agent_id.
--
-- Answers: who is overloaded RIGHT NOW?
-- For how performance has trended over time, use fact_agent_daily.
--
-- WHY derived from fact_agent_daily (not stg_threads directly):
--   1. Single source — stg_threads is read once in fact_agent_daily.
--   2. Speed metrics use correct weighted average (sum/count),
--      not avg() which misweights unequal-volume days.
--   3. Clear lineage: staging → fact_agent_daily → dim_agent_workload.
--
-- NOTE on open_threads:
--   SUM(threads_open_eod) across all dates. threads_open_eod is evaluated
--   at model-run time, so the sum is the true current open queue per agent.
--   Caveat: re-assignments after creation are not reflected — thread stays
--   in the original agent's open count. Production fix: thread_assignment_history.
--
-- NOTE on companies_breached_on_sla:
--   SUM of daily distinct company counts — overcounts if a company breached
--   across multiple days. Treat as an upper-bound signal, not an exact distinct.
-- ============================================================

with all_days as (
    select * from {{ ref('fact_agent_daily') }}
),

-- latest rolling-window values per agent (trailing 7d at most recent date)
latest_per_agent as (
    select
        agent_id,
        max(activity_date)              as latest_date,
        max(rolling_7d_threads_assigned)
            filter (where activity_date = max(activity_date) over (partition by agent_id))
                                        as last_7d_threads,
        max(rolling_7d_avg_frt_mins)
            filter (where activity_date = max(activity_date) over (partition by agent_id))
                                        as last_7d_avg_frt_mins
    from all_days
    group by 1
),

agent_totals as (
    select
        ad.agent_id,
        ad.agent_name,

        -- ── Volume (additive — sum across all time) ───────────────
        sum(ad.threads_assigned)                                        as total_threads,
        sum(ad.threads_open_eod)                                        as open_threads,
        sum(ad.threads_resolved)                                        as resolved_threads,
        sum(ad.threads_escalated)                                       as escalated_threads,
        sum(ad.high_priority_open_eod)                                  as open_high_priority,

        -- ── Speed (weighted average: sum / count) ─────────────────
        round(
            sum(ad.sum_frt_mins) / nullif(sum(ad.frt_response_count), 0), 1
        )                                                               as avg_frt_mins,
        round(
            sum(ad.sum_ttr_mins) / nullif(sum(ad.ttr_resolved_count), 0), 1
        )                                                               as avg_ttr_mins,

        -- ── Channel mix (additive) ────────────────────────────────
        sum(ad.slack_threads)                                           as slack_threads,
        sum(ad.email_threads)                                           as email_threads,
        sum(ad.chat_threads)                                            as chat_threads,
        sum(ad.api_threads)                                             as api_threads,

        -- ── SLA (additive) ────────────────────────────────────────
        sum(ad.sla_breaches)                                            as sla_breaches,
        sum(ad.companies_breached)                                      as companies_breached_on_sla,

        -- ── Trailing 7-day context (from latest_per_agent) ────────
        lpa.last_7d_threads,
        lpa.last_7d_avg_frt_mins,
        lpa.latest_date                                                 as last_active_date

    from all_days ad
    left join latest_per_agent lpa on ad.agent_id = lpa.agent_id
    group by ad.agent_id, ad.agent_name, lpa.last_7d_threads, lpa.last_7d_avg_frt_mins, lpa.latest_date
)

select
    agent_id,
    agent_name,

    -- Volume
    total_threads,
    open_threads,
    resolved_threads,
    escalated_threads,
    open_high_priority,

    -- Speed
    avg_frt_mins,
    avg_ttr_mins,

    -- Channel mix
    slack_threads,
    email_threads,
    chat_threads,
    api_threads,

    -- SLA
    sla_breaches,
    companies_breached_on_sla,

    -- Trailing 7d (for context alongside the current snapshot)
    last_7d_threads,
    last_7d_avg_frt_mins,

    -- Workload classification
    case
        when open_threads > 20  then 'overloaded'
        when open_threads > 12  then 'busy'
        when open_threads > 5   then 'normal'
        else 'light'
    end                                                                 as workload_status,

    last_active_date

from agent_totals
order by open_threads desc
