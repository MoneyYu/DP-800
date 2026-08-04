/*
    M07 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 7 CI/CD project/runtime objects and
    returns Module 7 to a NotStarted baseline. The canonical core is left intact.
    The buildable SQL project artifact (M07/common/Dp800.Database) on disk is a
    separate CI/CD asset and is not affected by this database reset.

    Module-owned objects removed (dependency-safe order):
      * catalog.usp_LogInventoryChange (stored procedure)
      * catalog.InventoryChangeLog     (change-log table)
      * ops.DeploymentLog              (deployment-log table)

    M07 has no downstream module dependents, so only M07 is reset.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Guard 1: refuse to run against anything but AdventureGearAI. */
IF DB_NAME() <> N'AdventureGearAI'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'M07 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M07 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (procedure -> tables). The canonical
   catalog.Products core referenced by the change log is never dropped.
--------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS catalog.usp_LogInventoryChange;
DROP TABLE IF EXISTS catalog.InventoryChangeLog;
DROP TABLE IF EXISTS ops.DeploymentLog;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 7 (no dependents).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (7);
GO

SET NOEXEC OFF;
GO
PRINT N'M07 reset complete: CI/CD objects removed; M07 marked NotStarted.';
GO
