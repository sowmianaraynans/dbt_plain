-- fact_customer_cohorts.sql
-- ============================================================
-- CUSTOMER COHORT RETENTION
-- ============================================================
-- Acquisition volume and current retention health per monthly cohort.
--
-- Limitation: based on current status snapshot, not a time-series.
-- In production, replace with a daily status history table (from CDC)
-- to compute true month-by-month retention curves.
--
-- Grain: one row per (cohort_month, company_tier)
-- ============================================================

with customers as (
    select * from {{ ref('stg_customers') }}
),

cohorts as (
    select
        date_trunc('month', created_at)::date                           as cohort_month,
        company_tier,

        -- Acquisition
        count(*)                                                        as cohort_size,

        -- Current status breakdown
        countif(is_active)                                              as active_customers,
        countif(status = 'idle')                                        as idle_customers,
        countif(is_churned)                                             as churned_customers,

        -- Rates (point-in-time as of today)
        round(
            100.0 * countif(is_active) / nullif(count(*), 0), 1
        )                                                               as retention_pct,

        round(
            100.0 * countif(is_churned) / nullif(count(*), 0), 1
        )                                                               as churn_pct,

        round(
            100.0 * countif(status = 'idle') / nullif(count(*), 0), 1
        )                                                               as idle_pct,

        -- Cohort age
        datediff('month',
            date_trunc('month', created_at)::date,
            current_date
        )                                                               as months_since_acquisition

    from customers
    group by 1, 2
)

select * from cohorts
order by cohort_month desc, company_tier
