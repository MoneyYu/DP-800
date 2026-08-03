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

