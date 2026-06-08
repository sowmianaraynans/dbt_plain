-- stg_threads.sql
-- Cleaned thread records. Threads are the core interaction unit in Plain —
-- one thread = one customer conversation, regardless of channel.

with source as (
    select * from {{ ref('raw_threads') }}
),

deduped as (
    select *,
        row_number() over (partition by id order by updated_at desc) as rn
    from source
),

final as (
    select
        id                                              as thread_id,
        external_id,
        customer_id,
        company_id,
        tenant_id,
        company_tier,
        title,
        status,
        status_detail,
        priority,
        channel,
        label,
        assigned_agent_id,
        assigned_agent_name,

        -- timing fields (minutes)
        first_response_time_mins::integer               as first_response_time_mins,
        resolution_time_mins::integer                   as resolution_time_mins,
        message_count::integer                          as message_count,

        -- derived booleans
        status = 'done'                                 as is_resolved,
        is_escalated::boolean                           as is_escalated,
        priority in ('urgent', 'high')                  as is_high_priority,
        assigned_agent_id is not null                   as is_assigned,

        created_at::timestamp                           as created_at,
        updated_at::timestamp                           as updated_at,
        resolved_at::timestamp                          as resolved_at,
        date_trunc('week', created_at::timestamp)       as created_week,
        date_trunc('month', created_at::timestamp)      as created_month
    from deduped
    where rn = 1
)

select * from final
