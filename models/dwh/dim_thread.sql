-- dim_thread.sql
-- ============================================================
-- THREAD DIMENSION
-- ============================================================
-- Thread-level descriptor enriched with customer context
-- and computed classification buckets.
--
-- Sources from fact_threads (which already joins company dims).
-- Adds: customer_name, customer_email, resolution_bucket, age_hours_open.
--
-- Use for: ad-hoc filtering, thread-level drill-down in BI,
-- resolution time distribution analysis.
-- For aggregated metrics, use fact_thread_measures or mart_support_monthly.
--
-- Grain: one row per thread_id
-- ============================================================

with threads as (
    select * from {{ ref('fact_threads') }}
),

customers as (
    select
        customer_id,
        full_name   as customer_name,
        email       as customer_email
    from {{ ref('stg_customers') }}
),

final as (
    select
        -- ── Identity ──────────────────────────────────────────────
        t.thread_id,

        -- ── Customer / Company ────────────────────────────────────
        t.customer_id,
        cu.customer_name,
        cu.customer_email,
        t.company_id,
        t.company_name,
        t.company_tier,
        t.region,
        t.tenant_id,

        -- ── Thread attributes ─────────────────────────────────────
        t.channel,
        t.priority,
        t.label,
        t.assigned_agent_id,

        -- ── Status flags ──────────────────────────────────────────
        t.is_resolved,
        t.is_escalated,
        t.is_high_priority,
        t.is_assigned,

        -- ── Speed metrics ─────────────────────────────────────────
        t.first_response_time_mins,
        t.resolution_time_mins,
        t.message_count,

        -- ── Resolution bucket (for distribution analysis) ─────────
        case
            when not t.is_resolved                              then 'open'
            when t.resolution_time_mins <= 60                   then 'within_1h'
            when t.resolution_time_mins <= 480                  then 'within_8h'
            when t.resolution_time_mins <= 1440                 then 'within_24h'
            when t.resolution_time_mins <= 10080                then 'within_7d'
            else 'over_7d'
        end                                                     as resolution_bucket,

        -- ── Thread age (open threads only) ────────────────────────
        case
            when not t.is_resolved
            then datediff('hour', t.created_at, current_timestamp)
        end                                                     as age_hours_open,

        -- ── Timestamps ────────────────────────────────────────────
        t.created_date,
        t.resolved_date,
        t.created_at,
        t.updated_at,
        t.resolved_at

    from threads t
    left join customers cu on t.customer_id = cu.customer_id
)

select * from final
