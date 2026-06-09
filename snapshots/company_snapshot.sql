-- company_snapshot.sql
-- ============================================================
-- COMPANY STATUS SNAPSHOT (SCD Type 2)
-- ============================================================
-- Tracks changes to company status over time.
-- Run `dbt snapshot` on a schedule (daily or weekly) to build history.
--
-- Each run compares stg_companies to the previous snapshot.
-- When is_active, company_tier, or mrr_usd changes, a new row is
-- appended with dbt_valid_from = now and the previous row gets
-- dbt_valid_to = now. Unchanged companies get no new row.
--
-- This is the production path to fact_company_cohorts period history.
-- For the demo (static seeds), company_monthly_status.csv simulates
-- what this table would look like after months of scheduled runs.
--
-- Schema produced:
--   company_id, company_name, company_tier, is_active, mrr_usd,
--   updated_at, dbt_scd_id, dbt_updated_at, dbt_valid_from, dbt_valid_to
-- ============================================================

{% snapshot company_snapshot %}

{{
    config(
        target_schema = 'snapshots',
        unique_key    = 'company_id',
        strategy      = 'timestamp',
        updated_at    = 'updated_at',
        invalidate_hard_deletes = true,
    )
}}

select
    company_id,
    company_name,
    company_tier,
    region,
    is_active,
    is_paying,
    mrr_usd,
    updated_at
from {{ ref('stg_companies') }}

{% endsnapshot %}
