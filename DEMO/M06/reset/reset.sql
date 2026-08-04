/*
    M06 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 6 performance workload and returns Module
    6 to a NotStarted baseline. The canonical core is left intact.

    Module-owned objects removed:
      * ops.PerformanceOrders (and its covering index IX_PerformanceOrders_CustomerDate,
        dropped implicitly with the table)

    Query Store is a database-level setting that many later modules can also rely
    on; this reset intentionally leaves Query Store ENABLED and only removes the
    module's operational workload data. Disabling Query Store is a database-level
    concern handled by the full reset, not this module reset.

    M06 has no downstream module dependents, so only M06 is reset.

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
    RAISERROR(N'M06 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M06 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned workload only. Dropping the table also drops its
   covering index. Query Store remains enabled at the database level.
--------------------------------------------------------------------------- */
DROP TABLE IF EXISTS ops.PerformanceOrders;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 6 (no dependents).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (6);
GO

SET NOEXEC OFF;
GO
PRINT N'M06 reset complete: performance workload removed (Query Store left enabled); M06 marked NotStarted.';
GO
