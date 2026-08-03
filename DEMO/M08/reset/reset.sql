/*
    M08 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 8 API projection views and returns Module
    8 to a NotStarted baseline. The canonical catalog core the views project over
    is left intact.

    Module-owned objects removed:
      * api.InventoryAvailability (view)
      * api.ProductCatalog        (view)
      * api.Products              (view)
      * api.Categories            (view)

    M08 has no downstream module dependents, so only M08 is reset.

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
    RAISERROR(N'M08 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M08 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned views only. The canonical catalog core is never dropped.
--------------------------------------------------------------------------- */
DROP VIEW IF EXISTS api.InventoryAvailability;
DROP VIEW IF EXISTS api.ProductCatalog;
DROP VIEW IF EXISTS api.Products;
DROP VIEW IF EXISTS api.Categories;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 8 (no dependents).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (8);
GO

SET NOEXEC OFF;
GO
PRINT N'M08 reset complete: api.* projection views removed; M08 marked NotStarted.';
GO
