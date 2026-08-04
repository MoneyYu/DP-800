/* INTERACTIVE — run in session A after 07-isolation-rcsi-probe.sql. */
USE [DP800_M06_IsolationProbe];
GO

BEGIN TRANSACTION;
UPDATE dbo.IsolationProbe SET Value = N'Uncommitted writer value' WHERE ProbeID = 1;
WAITFOR DELAY '00:00:20';
ROLLBACK;
GO
