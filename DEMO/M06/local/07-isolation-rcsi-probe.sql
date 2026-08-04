/*
    M06 local/07-isolation-rcsi-probe.sql (INTERACTIVE — excluded from runner)

    Creates the exact disposable database used for the READ COMMITTED/RCSI
    comparison. AdventureGearAI is never changed. Run this script, then use
    09-isolation-writer.sql and 10-isolation-reader.sql in two sessions while
    RCSI is OFF. Run 11-enable-rcsi.sql and repeat the two-session test to
    observe the RCSI behavior. Finish with 12-isolation-rcsi-cleanup.sql.
*/
USE master;
GO

IF DB_ID(N'DP800_M06_IsolationProbe') IS NOT NULL
BEGIN
    ALTER DATABASE [DP800_M06_IsolationProbe] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [DP800_M06_IsolationProbe];
END;
GO

CREATE DATABASE [DP800_M06_IsolationProbe];
ALTER DATABASE [DP800_M06_IsolationProbe] SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
GO

USE [DP800_M06_IsolationProbe];
GO

CREATE TABLE dbo.IsolationProbe
(
    ProbeID int NOT NULL CONSTRAINT PK_IsolationProbe PRIMARY KEY,
    Value nvarchar(50) NOT NULL
);
INSERT dbo.IsolationProbe (ProbeID, Value) VALUES (1, N'Committed baseline');
GO

DECLARE @engineEdition int = CONVERT(int, SERVERPROPERTY('EngineEdition'));
SELECT
    DB_NAME() AS ProbeDatabase,
    d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
    @engineEdition AS EngineEdition,
    CASE
        WHEN @engineEdition = 5 THEN N'Azure SQL Database: CDC/RCSI services are platform-managed; this disposable probe still demonstrates database RCSI.'
        WHEN @engineEdition = 8 THEN N'Azure SQL Managed Instance: SQL Agent is available; this disposable probe demonstrates the same READ COMMITTED/RCSI boundary.'
        ELSE N'Local SQL Server: SQL Agent availability is separate from RCSI; this disposable probe avoids changing AdventureGearAI.'
    END AS LocalAzureBoundary
FROM sys.databases AS d
WHERE d.name = DB_NAME();

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT N'RCSI OFF: start 09-isolation-writer.sql, then run 10-isolation-reader.sql. The reader waits for the writer lock.' AS ExpectedBehavior;
GO
