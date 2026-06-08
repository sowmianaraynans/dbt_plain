-- dim_agent_workload.sql
-- ============================================================
-- AGENT WORKLOAD
-- ============================================================
-- Helps support leads understand capacity and performance.
-- Answers: who is overloaded? who resolves fastest?
--          where are SLA breaches concentrated by agent?
--
-- Grain: one row per assigned_agent_id (current snapshot)
-- ============================================================

with threads as (
    select * from {{ ref('stg_threads') }}
),

breaches as (
    select * from {{ ref('stg_sla_breaches') }}
),

thread_agg as (
    select
        assigned_agent_id,
        assigned_agent_name,

        count(*)                                        as total_threads,
        countif(not is_resolved)                        as open_threads,
        countif(is_resolved)                            as resolved_threads,
        countif(is_escalated)                           as escalated_threads,
        countif(is_high_priority and not is_resolved)   as open_high_priority,

        round(avg(first_response_time_mins), 1)         as avg_frt_mins,
        round(avg(resolution_time_mins), 1)             as avg_ttr_mins,
        round(median(resolution_time_mins), 1)          as median_ttr_mins,

        -- channel mix
        countif(channel = 'slack')                      as slack_threads,
        countif(channel = 'email')                      as email_threads,
        countif(channel = 'chat')                       as chat_threads,

        max(updated_at)                                 as last_activity_at

    from threads
    where assigned_agent_id is not null
    group by 1, 2
),

breach_agg as (
    select
        assigned_agent_id,
        count(*)                    as sla_breaches,
        count(distinct company_id)  as companies_breached
    from breaches
    group by 1
),

final as (
    select
        ta.assigned_agent_id        as agent_id,
        ta.assigned_agent_name      as agent_name,

        -- Volume
        ta.total_threads,
        ta.open_threads,
        ta.resolved_threads,
        ta.escalated_threads,
        ta.open_high_priority,

        -- Speed
        ta.avg_frt_mins,
        ta.avg_ttr_mins,
        ta.median_ttr_mins,

        -- Channel mix
        ta.slack_threads,
        ta.email_threads,
        ta.chat_threads,

        -- SLA
        coalesce(ba.sla_breaches, 0)            as sla_breaches,
        coalesce(ba.companies_breached, 0)      as companies_breached_on_sla,

        -- Workload flag (simple capacity signal)
        case
            when ta.open_threads > 20           then 'overloaded'
            when ta.open_threads > 12           then 'busy'
            when ta.open_threads > 5            then 'normal'
            else 'light'
        end                                     as workload_status,

        ta.last_activity_at

    from thread_agg ta
    left join breach_agg ba using (assigned_agent_id)
)

select * from final
order by open_threads desc
