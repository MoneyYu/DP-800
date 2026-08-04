/*
    INTERACTIVE — run in session B while 09-isolation-writer.sql holds its lock.
    With RCSI OFF this READ COMMITTED query waits. After 11-enable-rcsi.sql,
    it returns the committed baseline without waiting.
*/
USE master;
GO

CREATE TABLE #OwnedProbes (DatabaseName sysname NOT NULL PRIMARY KEY);
DECLARE @CandidateDatabase sysname;
DECLARE @ProbeDatabase sysname;
DECLARE @Sql nvarchar(max);
DECLARE ProbeCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE name LIKE N'DP800_M06_IsolationProbe[_]%';

OPEN ProbeCursor;
FETCH NEXT FROM ProbeCursor INTO @CandidateDatabase;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'USE ' + QUOTENAME(@CandidateDatabase) + N';
        IF EXISTS
        (
            SELECT 1
            FROM sys.extended_properties
            WHERE class = 0
              AND name = N''DP800.M06.IsolationProbe''
              AND value = N''DP800 M06 owned isolation probe''
        )
            INSERT #OwnedProbes (DatabaseName) VALUES (@DatabaseName);';
    EXEC sys.sp_executesql @Sql, N'@DatabaseName sysname', @DatabaseName = @CandidateDatabase;
    FETCH NEXT FROM ProbeCursor INTO @CandidateDatabase;
END;
CLOSE ProbeCursor;
DEALLOCATE ProbeCursor;

IF (SELECT COUNT(*) FROM #OwnedProbes) <> 1
    THROW 51010, N'Expected exactly one M06-owned isolation probe. Run 07 first and clean up any previous M06-owned probe.', 1;
SELECT @ProbeDatabase = DatabaseName FROM #OwnedProbes;

SET @Sql = N'USE ' + QUOTENAME(@ProbeDatabase) + N';'
         + N'SET TRANSACTION ISOLATION LEVEL READ COMMITTED;'
         + N'SELECT
    d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
    p.ProbeID,
    p.Value,
    SYSUTCDATETIME() AS ReadAtUtc
FROM dbo.IsolationProbe AS p
CROSS JOIN sys.databases AS d
WHERE d.name = DB_NAME() AND p.ProbeID = 1;';
EXEC sys.sp_executesql @Sql;
GO
