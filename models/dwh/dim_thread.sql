-- dim_thread.sql
-- ============================================================
-- THREAD DIMENSION
-- ============================================================
-- Thread attributes used for reporting and downstream joins.
-- Grain: one row per thread_id.
-- ============================================================

select * from {{ ref('stg_threads') }}
