/* Run after the RCSI-OFF comparison, then repeat writer and reader sessions. */
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

SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@ProbeDatabase)
         + N' SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;'
         + N'USE ' + QUOTENAME(@ProbeDatabase) + N';
'
         + N'SET TRANSACTION ISOLATION LEVEL READ COMMITTED;'
         + N'SELECT d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
       N''RCSI ON: READ COMMITTED reads the committed version while the writer lock is held.'' AS ExpectedBehavior
FROM sys.databases AS d
WHERE d.name = DB_NAME();';
EXEC sys.sp_executesql @Sql;
GO
