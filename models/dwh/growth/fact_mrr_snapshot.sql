-- fact_mrr_snapshot.sql
-- ============================================================
-- MRR / ARR SNAPSHOT
-- ============================================================
-- Current revenue snapshot by tier. Answers: what is our ARR?
-- Which tier drives the most revenue? What is revenue per customer?
--
-- Limitation: mrr_usd on companies is a static field captured at
-- ingestion time — not a time-series. MRR movement (expansion,
-- contraction, churn revenue) requires Stripe subscription events.
-- This is the starting point; Stripe is the next data source to add.
--
-- Grain: one row per company_tier
-- ============================================================

with companies as (
    select * from {{ ref('stg_companies') }}
),

customer_counts as (
    select
        company_id,
        count(*)            as total_customers,
        countif(is_active)  as active_customers,
        countif(is_churned) as churned_customers
    from {{ ref('stg_customers') }}
    group by 1
),

company_detail as (
    select
        co.company_id,
        co.company_tier,
        co.mrr_usd,
        co.is_active,
        coalesce(cu.total_customers, 0)    as total_customers,
        coalesce(cu.active_customers, 0)   as active_customers,
        coalesce(cu.churned_customers, 0)  as churned_customers
    from companies co
    left join customer_counts cu using (company_id)
    where co.company_tier != 'free'
),

final as (
    select
        company_tier,

        -- Account counts
        count(company_id)                                               as total_companies,
        countif(is_active)                                              as active_companies,

        -- MRR
        sum(mrr_usd)                                                    as total_mrr_usd,
        round(avg(mrr_usd), 0)                                          as avg_mrr_per_company,
        max(mrr_usd)                                                    as max_mrr_usd,

        -- ARR
        sum(mrr_usd) * 12                                               as total_arr_usd,

        -- Customers
        sum(total_customers)                                            as total_customers,
        sum(active_customers)                                           as active_customers,

        -- Revenue efficiency
        round(
            sum(mrr_usd)::float / nullif(sum(active_customers), 0), 2
        )                                                               as mrr_per_active_customer

    from company_detail
    group by 1
)

select * from final
order by total_mrr_usd desc
