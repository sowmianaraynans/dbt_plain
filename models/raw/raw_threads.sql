-- raw_threads.sql
-- Direct mirror of Plain's /graphql/threads API response.
-- Includes all fields: status, priority, channel, SLA timing, assignment.

select * from {{ source('seeds', 'threads') }}
