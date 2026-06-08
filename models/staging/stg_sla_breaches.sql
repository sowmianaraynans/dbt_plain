-- stg_sla_breaches.sql
-- SLA breach records — one row per breach event.
-- Plain SLAs are defined per tier: first_response_time and next_response_time.

with source as (
    select * from {{ ref('raw_sla_breaches') }}
),

final as (
    select
        id                              as breach_id,
        thread_id,
        customer_id,
        company_id,
        company_tier,
        sla_type,
        target_minutes::integer         as target_minutes,
        actual_minutes::integer         as actual_minutes,
        breach_by_minutes::integer      as breach_by_minutes,
        priority,
        channel,
        assigned_agent_id,
        assigned_agent_name,
        breached_at::timestamp          as breached_at,
        date_trunc('week', breached_at::timestamp)   as breach_week,
        date_trunc('month', breached_at::timestamp)  as breach_month
    from source
)

select * from final
