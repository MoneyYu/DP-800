/* INTERACTIVE — run in session A after 07-isolation-rcsi-probe.sql. */
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

SET @Sql = N'USE ' + QUOTENAME(@ProbeDatabase) + N';
BEGIN TRANSACTION;
UPDATE dbo.IsolationProbe SET Value = N''Uncommitted writer value'' WHERE ProbeID = 1;
WAITFOR DELAY ''00:00:20'';
ROLLBACK;';
EXEC sys.sp_executesql @Sql;
GO
