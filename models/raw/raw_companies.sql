-- raw_companies.sql
-- Direct mirror of Plain's /graphql/companies API response.
-- Includes all fields: account-level metadata, tier, region, and MRR.

select * from {{ source('seeds', 'companies') }}
