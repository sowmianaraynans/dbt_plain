-- raw_sla_breaches.sql
-- Direct mirror of Plain's /graphql/slaBreaches API response.
-- Captures every SLA breach event from Plain.

select * from {{ source('seeds', 'sla_breaches') }}
