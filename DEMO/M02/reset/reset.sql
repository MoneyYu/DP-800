/*
    M02 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 2 programmability objects and returns
    Module 2 to a NotStarted baseline. The canonical sales/customer/catalog core
    is left intact.

    Module-owned objects removed (dependency-safe order):
      * sales.trg_OrderStatusAudit   (trigger on sales.Orders)
      * sales.usp_AddOrderItem       (stored procedure)
      * sales.fn_OrderTotal          (scalar function)
      * sales.fn_CustomerOrders      (inline table-valued function)
      * sales.vw_CustomerOrderSummary(view)
      * sales.OrderStatusAudit       (audit sink table)

    M02 has no downstream module dependents, so only M02 is reset.

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
    RAISERROR(N'M02 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M02 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (trigger -> proc/functions -> view ->
   audit table). The canonical sales.Orders/OrderItems core is never dropped.
--------------------------------------------------------------------------- */
DROP TRIGGER IF EXISTS sales.trg_OrderStatusAudit;
DROP PROCEDURE IF EXISTS sales.usp_AddOrderItem;
DROP FUNCTION IF EXISTS sales.fn_OrderTotal;
DROP FUNCTION IF EXISTS sales.fn_CustomerOrders;
DROP VIEW IF EXISTS sales.vw_CustomerOrderSummary;
DROP TABLE IF EXISTS sales.OrderStatusAudit;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 2 (no dependents).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (2);
GO

SET NOEXEC OFF;
GO
PRINT N'M02 reset complete: programmability objects removed; M02 marked NotStarted.';
GO
