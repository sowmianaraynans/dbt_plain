-- stg_thread_events.sql
-- Cleaned thread event records. Events capture every status transition,
-- assignment change, message, and escalation within a thread.
-- Used for timeline analysis and time-to-first-response calculations.

with source as (
    select * from "plain_analytics"."main_raw"."raw_thread_events"
),

final as (
    select
        id                              as event_id,
        thread_id,
        customer_id,
        company_id,
        event_type,
        actor_type,
        actor_id,
        occurred_at::timestamp          as occurred_at
    from source
)

select * from final