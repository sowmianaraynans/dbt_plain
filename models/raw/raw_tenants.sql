-- raw_tenants.sql
-- Direct mirror of Plain's /graphql/tenants API response.
-- This is used for tenant-level context in the customer spine.

select * from {{ source('seeds', 'tenants') }}
