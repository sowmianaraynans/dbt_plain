-- raw_customers.sql
-- Direct mirror of Plain's /graphql/customers API response.
-- Nothing is dropped, renamed, or cast here.
-- Append-only — this is the source of truth for all customer data.

select * from {{ source('seeds', 'customers') }}
