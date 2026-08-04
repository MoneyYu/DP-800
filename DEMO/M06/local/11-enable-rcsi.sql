/* Run after the RCSI-OFF comparison, then repeat 09-isolation-writer.sql and 10-isolation-reader.sql. */
USE master;
GO

ALTER DATABASE [DP800_M06_IsolationProbe] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

USE [DP800_M06_IsolationProbe];
GO
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
       N'RCSI ON: READ COMMITTED reads the committed version while the writer lock is held.' AS ExpectedBehavior
FROM sys.databases AS d
WHERE d.name = DB_NAME();
GO
