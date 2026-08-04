/*
    M06 local/04-observe-blocking.sql  (INTERACTIVE — excluded from the runner manifest)

    Session 3 of the blocking demo. Run manually to observe the blocked/blocking
    relationship while 02-blocker.sql and 03-blocked.sql are active.
*/
SELECT
    r.session_id AS BlockedSession,
    r.blocking_session_id AS BlockingSession,
    r.wait_type,
    r.wait_time AS WaitTimeMs,
    r.wait_resource,
    textInfo.text AS BlockedStatement
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS textInfo
WHERE r.blocking_session_id <> 0;
GO
