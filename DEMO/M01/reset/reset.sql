/*
    M01 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database (the only approved database-level reset lives in
    DEMO/reset/reset-adventuregear.sql). Instead it removes ONLY the objects that
    Module 1 owns and returns Module 1 plus every dependent module to a
    NotStarted baseline. The canonical ecommerce core (catalog/sales/customer
    tables and seed data) provisioned by the bootstrap is left intact.

    Module-owned objects removed (dependency-safe order):
      * catalog.ProductRelatedTo / catalog.ProductNode      (SQL graph edge/node)
      * catalog.ProductPrice + catalog.ProductPriceHistory  (system-versioned temporal)
      * sales.PartitionedOrders + partition scheme/function (range partitioning)
      * catalog.Products.MetadataFrame + IX_Products_MetadataFrame (computed column/index)

    Dependency/staleness reset: every module depends (transitively) on M01, so a
    M01 reset marks M02..M11 stale (NotStarted) as well, clearing their timestamps
    and errors so the runner reapplies them from a clean baseline.

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
    RAISERROR(N'M01 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M01 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (dependency-safe order). The canonical
   catalog.Products/catalog.Categories/sales.* core is never dropped.
--------------------------------------------------------------------------- */
IF OBJECT_ID(N'catalog.ProductRelatedTo', N'U') IS NOT NULL DROP TABLE catalog.ProductRelatedTo;
IF OBJECT_ID(N'catalog.ProductNode', N'U') IS NOT NULL DROP TABLE catalog.ProductNode;

IF OBJECT_ID(N'catalog.ProductPrice', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID(N'catalog.ProductPrice') AND temporal_type = 2)
        ALTER TABLE catalog.ProductPrice SET (SYSTEM_VERSIONING = OFF);
    DROP TABLE catalog.ProductPrice;
END;
DROP TABLE IF EXISTS catalog.ProductPriceHistory;

DROP TABLE IF EXISTS sales.PartitionedOrders;
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'PS_AdventureGear_OrderDate')
    DROP PARTITION SCHEME PS_AdventureGear_OrderDate;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'PF_AdventureGear_OrderDate')
    DROP PARTITION FUNCTION PF_AdventureGear_OrderDate;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'IX_Products_MetadataFrame')
    DROP INDEX IX_Products_MetadataFrame ON catalog.Products;
IF COL_LENGTH(N'catalog.Products', N'MetadataFrame') IS NOT NULL
    ALTER TABLE catalog.Products DROP COLUMN MetadataFrame;
GO

/* ---------------------------------------------------------------------------
   State reset: M01 and every dependent module (M02..M11) become NotStarted.
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
GO

SET NOEXEC OFF;
GO
PRINT N'M01 reset complete: module objects removed; M01-M11 marked NotStarted.';
GO
