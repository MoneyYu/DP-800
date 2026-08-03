/*
    M05 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 5 security objects and returns Module 5
    to a NotStarted baseline. The canonical customer.Customers core is left
    intact.

    Module-owned objects removed (dependency-safe order):
      * security.CustomerRegionPolicy  (Row-Level Security policy)
      * security.fn_RegionFilter       (RLS predicate function)
      * AdventureGearMaskedReader      (contained demo user)
      * AdventureGearWestReader        (contained demo user)
      * security.SecureCustomers       (masked companion projection table)

    M05 has no downstream module dependents, so only M05 is reset.

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
    RAISERROR(N'M05 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M05 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (policy -> predicate -> users -> companion
   table). The canonical customer.Customers core is never dropped.
--------------------------------------------------------------------------- */
DROP SECURITY POLICY IF EXISTS security.CustomerRegionPolicy;
DROP FUNCTION IF EXISTS security.fn_RegionFilter;
DROP USER IF EXISTS AdventureGearMaskedReader;
DROP USER IF EXISTS AdventureGearWestReader;
DROP TABLE IF EXISTS security.SecureCustomers;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 5 (no dependents).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (5);
GO

SET NOEXEC OFF;
GO
PRINT N'M05 reset complete: security objects removed; M05 marked NotStarted.';
GO
