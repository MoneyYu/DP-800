/*
    M03 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 3 advanced-T-SQL teaching objects and
    returns Module 3 to a NotStarted baseline. The canonical core and the
    operational tracking tables (ops.DemoEnvironment / ops.DemoModuleState) are
    left intact.

    Module-owned objects removed (dependency-safe order):
      * ops.ReportsTo          (SQL graph edge)
      * ops.EmployeeNode       (SQL graph node)
      * ops.EmployeeHierarchy  (self-referencing hierarchy table)

    M03 has no downstream module dependents, so only M03 is reset.

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
    RAISERROR(N'M03 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M03 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (edge -> node -> hierarchy). The
   ops.DemoEnvironment / ops.DemoModuleState operational tables are never dropped.
--------------------------------------------------------------------------- */
IF OBJECT_ID(N'ops.ReportsTo', N'U') IS NOT NULL DROP TABLE ops.ReportsTo;
IF OBJECT_ID(N'ops.EmployeeNode', N'U') IS NOT NULL DROP TABLE ops.EmployeeNode;
DROP TABLE IF EXISTS ops.EmployeeHierarchy;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 3 (no dependents).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (3);
GO

SET NOEXEC OFF;
GO
PRINT N'M03 reset complete: advanced teaching objects removed; M03 marked NotStarted.';
GO
