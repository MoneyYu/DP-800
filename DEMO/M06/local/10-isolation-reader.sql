/*
    INTERACTIVE — run in session B while 09-isolation-writer.sql holds its lock.
    With RCSI OFF this READ COMMITTED query waits. After 11-enable-rcsi.sql,
    it returns the committed baseline without waiting.
*/
USE [DP800_M06_IsolationProbe];
GO

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT
    d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
    p.ProbeID,
    p.Value,
    SYSUTCDATETIME() AS ReadAtUtc
FROM dbo.IsolationProbe AS p
CROSS JOIN sys.databases AS d
WHERE d.name = DB_NAME() AND p.ProbeID = 1;
GO
