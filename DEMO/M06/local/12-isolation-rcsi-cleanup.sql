/* Removes only a database marked as an M06-owned temporary isolation probe. */
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

IF (SELECT COUNT(*) FROM #OwnedProbes) = 0
BEGIN
    PRINT N'No M06-owned isolation probe was found; no database was changed.';
    RETURN;
END;

IF (SELECT COUNT(*) FROM #OwnedProbes) <> 1
    THROW 51011, N'Refusing cleanup because multiple M06-owned isolation probes were found.', 1;

SELECT @ProbeDatabase = DatabaseName FROM #OwnedProbes;
SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@ProbeDatabase)
         + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;'
         + N'DROP DATABASE ' + QUOTENAME(@ProbeDatabase) + N';';
EXEC sys.sp_executesql @Sql;
GO
