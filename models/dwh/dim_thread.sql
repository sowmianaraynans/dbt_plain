-- dim_thread.sql
-- ============================================================
-- THREAD DIMENSION
-- ============================================================
-- Thread-level attributes enriched with company and customer context.
-- Used for ad-hoc analysis, filtering, and downstream joins.
-- Grain: one row per thread_id.
-- ============================================================

with threads as (
    select * from {{ ref('stg_threads') }}
),

companies as (
    select
        company_id,
        company_name,
        company_tier,
        region
    from {{ ref('stg_companies') }}
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
        t.external_id,

        -- ── Customer / Company ────────────────────────────────────
        t.customer_id,
        cu.customer_name,
        cu.customer_email,
        t.company_id,
        co.company_name,
        co.company_tier,
        co.region,
        t.tenant_id,

        -- ── Thread attributes ─────────────────────────────────────
        t.title,
        t.status,
        t.priority,
        t.channel,
        t.label,
        t.assigned_agent_id,
        t.assigned_agent_name,

        -- ── Status flags ──────────────────────────────────────────
        t.is_resolved,
        t.is_escalated,
        t.is_high_priority,

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
            then datediff(
                'hour',
                t.created_at,
                current_timestamp
            )
        end                                                     as age_hours_open,

        -- ── Timestamps ────────────────────────────────────────────
        t.created_at,
        t.updated_at,
        t.resolved_at

    from threads t
    left join companies co  using (company_id)
    left join customers cu  using (customer_id)
)

select * from final
