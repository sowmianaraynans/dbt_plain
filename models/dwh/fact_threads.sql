-- fact_threads.sql
-- ============================================================
-- THREAD-GRAIN FACT TABLE
-- ============================================================
-- The base fact table for all thread analytics.
-- One row per thread. All dimension keys and measures preserved.
--
-- This is the source of truth for:
--   fact_thread_measures  — daily aggregation for p90/median
--   mart_support_monthly  — company-grain mart for BI
--   dim_thread            — enriched with customer details and buckets
--   MetricFlow            — threads_daily semantic model
--
-- Company dimensions (company_name, region) are joined here once
-- so all downstream models get them without re-joining stg_companies.
--
-- Grain: one row per thread_id
-- ============================================================

with threads as (
    select * from {{ ref('stg_threads') }}
),

companies as (
    select
        company_id,
        company_name,
        region
    from {{ ref('stg_companies') }}
)

select
    -- ── Keys ──────────────────────────────────────────────────
    t.thread_id,
    t.company_id,
    t.customer_id,
    t.assigned_agent_id,
    t.tenant_id,

    -- ── Company dimensions ────────────────────────────────────
    co.company_name,
    t.company_tier,
    co.region,

    -- ── Thread dimensions ─────────────────────────────────────
    t.channel,
    t.priority,
    t.label,
    t.created_at::date                                          as created_date,
    t.resolved_at::date                                         as resolved_date,

    -- ── Status flags (measures at thread grain) ───────────────
    t.is_resolved,
    t.is_escalated,
    t.is_high_priority,
    t.is_assigned,

    -- ── Speed measures ────────────────────────────────────────
    t.first_response_time_mins,
    t.resolution_time_mins,
    t.message_count,

    -- ── Timestamps ────────────────────────────────────────────
    t.created_at,
    t.updated_at,
    t.resolved_at

from threads t
left join companies co on t.company_id = co.company_id
