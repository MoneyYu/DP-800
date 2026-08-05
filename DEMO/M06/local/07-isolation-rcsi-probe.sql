/*
    INTERACTIVE — creates a uniquely named, marked disposable database for the
    READ COMMITTED/RCSI comparison. AdventureGearAI is never changed.
*/
USE master;
GO

DECLARE @ProbeDatabase sysname =
    CONCAT(N'DP800_M06_IsolationProbe_', REPLACE(CONVERT(nvarchar(36), NEWID()), N'-', N''));
DECLARE @Sql nvarchar(max);

SET @Sql = N'CREATE DATABASE ' + QUOTENAME(@ProbeDatabase) + N';';
EXEC sys.sp_executesql @Sql;

SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@ProbeDatabase)
         + N' SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;'
         + N'USE ' + QUOTENAME(@ProbeDatabase) + N';'
         + N'EXEC sys.sp_addextendedproperty'
         + N' @name = N''DP800.M06.IsolationProbe'','
         + N' @value = N''DP800 M06 owned isolation probe'';'
         + N'CREATE TABLE dbo.IsolationProbe'
         + N'('
         + N'    ProbeID int NOT NULL CONSTRAINT PK_IsolationProbe PRIMARY KEY,'
         + N'    Value nvarchar(50) NOT NULL'
         + N');'
         + N'INSERT dbo.IsolationProbe (ProbeID, Value) VALUES (1, N''Committed baseline'');';
EXEC sys.sp_executesql @Sql;

DECLARE @engineEdition int = CONVERT(int, SERVERPROPERTY('EngineEdition'));
SELECT
    @ProbeDatabase AS ProbeDatabase,
    d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
    @engineEdition AS EngineEdition,
    CASE
        WHEN @engineEdition = 5 THEN N'Azure SQL Database: CDC/RCSI services are platform-managed; this disposable probe still demonstrates database RCSI.'
        WHEN @engineEdition = 8 THEN N'Azure SQL Managed Instance: SQL Agent is available; this disposable probe demonstrates the same READ COMMITTED/RCSI boundary.'
        ELSE N'Local SQL Server: SQL Agent availability is separate from RCSI; this disposable probe avoids changing AdventureGearAI.'
    END AS LocalAzureBoundary
FROM sys.databases AS d
WHERE d.name = @ProbeDatabase;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT N'RCSI OFF: start 09-isolation-writer.sql, then run 10-isolation-reader.sql. The reader waits for the writer lock.' AS ExpectedBehavior;
GO
