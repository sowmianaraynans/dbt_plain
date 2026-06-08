-- raw_thread_events.sql
-- Direct mirror of Plain's /graphql/threadEvents API response.
-- Raw event history for threads and customer interactions.

select * from {{ source('seeds', 'thread_events') }}
