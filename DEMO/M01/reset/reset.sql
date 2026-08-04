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
      * catalog.ProductJsonTeaching + IX_Products_ProductMetadata (native json)
      * In-Memory cache table, updatable ledger, sequence, constraints, and
        feature-detected external metadata

    Dependency/staleness reset: every module depends (transitively) on M01, so a
    M01 reset marks M02..M11 stale (NotStarted) as well, clearing their timestamps
    and errors so the runner reapplies them from a clean baseline.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    * 統一 AdventureGearAI 示範的模組範圍重設：絕不刪除資料庫；只移除模組 1 擁有的物件，並將 M01 與其相依模組重設為 NotStarted，保留 bootstrap 建立的標準核心。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Guard 1: refuse to run against anything but AdventureGearAI.
    * 保護條件 1：拒絕在 AdventureGearAI 以外的資料庫執行。
*/
IF DB_NAME() <> N'AdventureGearAI'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'M01 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
    * 保護條件 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
*/
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
   * 只依相依安全順序清除模組擁有的物件；標準核心不會被刪除。
--------------------------------------------------------------------------- */
/* CDC creates database-level DDL triggers that prevent dropping a
   memory-optimized table. M08 is the only module that enables CDC. Coordinate
   with its lifecycle lock, remove only its recorded capture, and disable
   database CDC only when M08 enabled it and no other capture remains. */
DECLARE @DisableCdcDatabase bit = 0;
DECLARE @M08CaptureInstance sysname;
DECLARE @M08CaptureTableObjectId int;
DECLARE @M08CaptureTableCreatedAt datetime;
DECLARE @ExpectedM08CaptureInstance sysname = N'AdventureGearM08Products';
DECLARE @M08CaptureExists bit = 0;
DECLARE @RemainingCaptureCount int = 0;
DECLARE @CdcOwnershipLockResult int;
DECLARE @CdcOwnershipLockHeld bit = 0;

EXEC @CdcOwnershipLockResult = sys.sp_getapplock
    @Resource = N'DP800.M08.CdcOwnership',
    @LockMode = N'Exclusive',
    @LockOwner = N'Session',
    @LockTimeout = 60000;

IF @CdcOwnershipLockResult < 0
    THROW 51083, 'M01 reset could not acquire the CDC ownership lock.', 1;

SET @CdcOwnershipLockHeld = 1;

BEGIN TRY
    IF OBJECT_ID(N'api.CdcRuntimeStatus', N'U') IS NOT NULL
       AND COL_LENGTH(N'api.CdcRuntimeStatus', N'M08CaptureInstance') IS NOT NULL
       AND COL_LENGTH(N'api.CdcRuntimeStatus', N'M08CaptureTableObjectId') IS NOT NULL
       AND COL_LENGTH(N'api.CdcRuntimeStatus', N'M08CaptureTableCreatedAt') IS NOT NULL
        SELECT
            @DisableCdcDatabase = DatabaseCdcEnabledByModule,
            @M08CaptureInstance = M08CaptureInstance,
            @M08CaptureTableObjectId = M08CaptureTableObjectId,
            @M08CaptureTableCreatedAt = M08CaptureTableCreatedAt
        FROM api.CdcRuntimeStatus
        WHERE CdcRuntimeStatusID = 1;

    IF @M08CaptureInstance = @ExpectedM08CaptureInstance
       AND EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
    BEGIN
        EXEC sys.sp_executesql
            N'
            SELECT @CaptureExists = CONVERT(bit, CASE WHEN EXISTS
            (
                SELECT 1
                FROM cdc.change_tables
                WHERE source_object_id = OBJECT_ID(N''catalog.Products'')
                  AND capture_instance = @CaptureInstance
                  AND OBJECT_ID(N''cdc.'' + capture_instance + N''_CT'') = @CaptureTableObjectId
                  AND EXISTS
                  (
                      SELECT 1
                      FROM sys.objects AS cdcTable
                      WHERE cdcTable.object_id = @CaptureTableObjectId
                        AND cdcTable.create_date = @CaptureTableCreatedAt
                  )
            ) THEN 1 ELSE 0 END);',
            N'@CaptureInstance sysname, @CaptureTableObjectId int, @CaptureTableCreatedAt datetime, @CaptureExists bit OUTPUT',
            @CaptureInstance = @ExpectedM08CaptureInstance,
            @CaptureTableObjectId = @M08CaptureTableObjectId,
            @CaptureTableCreatedAt = @M08CaptureTableCreatedAt,
            @CaptureExists = @M08CaptureExists OUTPUT;

        IF @M08CaptureExists = 1
        BEGIN
            EXEC sys.sp_cdc_disable_table
                @source_schema = N'catalog',
                @source_name = N'Products',
                @capture_instance = @ExpectedM08CaptureInstance;

            EXEC sys.sp_executesql
                N'SELECT @RemainingCount = COUNT(*) FROM cdc.change_tables;',
                N'@RemainingCount int OUTPUT',
                @RemainingCount = @RemainingCaptureCount OUTPUT;

            IF @DisableCdcDatabase = 1
               AND @RemainingCaptureCount = 0
                EXEC sys.sp_cdc_disable_db;
        END;
    END;

    IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
        THROW 51084, 'M01 reset cannot remove its memory-optimized table while externally owned CDC remains enabled.', 1;
END TRY
BEGIN CATCH
    IF @CdcOwnershipLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M08.CdcOwnership',
            @LockOwner = N'Session';
    THROW;
END CATCH;

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

/* JSON index and teaching table are M01-owned; catalog.Products itself remains
   canonical. Do not remove M01MemoryOptimized: dropping an XTP filegroup/file
   has been observed to hang containerized SQL Server instances.
*/
IF EXISTS (SELECT 1 FROM sys.json_indexes WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'IX_Products_ProductMetadata')
    DROP INDEX IX_Products_ProductMetadata ON catalog.Products;
DROP TABLE IF EXISTS catalog.ProductJsonTeaching;

DROP TABLE IF EXISTS catalog.ProductCacheInMemory;
IF @CdcOwnershipLockHeld = 1
BEGIN
    EXEC sys.sp_releaseapplock
        @Resource = N'DP800.M08.CdcOwnership',
        @LockOwner = N'Session';
    SET @CdcOwnershipLockHeld = 0;
END;

/* Dropping an updatable ledger can retain an engine-managed dropped-ledger
   system table for verification. It is intentional and must not be removed.
*/
IF OBJECT_ID(N'ops.InventoryLedger', N'U') IS NOT NULL
    DROP TABLE ops.InventoryLedger;

DROP TABLE IF EXISTS catalog.ProductSkuSequenceDemo;
IF OBJECT_ID(N'catalog.ProductSkuSequence', N'SO') IS NOT NULL
    DROP SEQUENCE catalog.ProductSkuSequence;

DROP TABLE IF EXISTS catalog.ProductConstraintViolationLog;
DROP TABLE IF EXISTS catalog.ProductConstraintChild;
DROP TABLE IF EXISTS catalog.ProductConstraintParent;

IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'catalog.ProductMetadataExternal'))
    DROP EXTERNAL TABLE catalog.ProductMetadataExternal;
IF EXISTS (SELECT 1 FROM sys.external_file_formats WHERE name = N'M01ProductMetadataFileFormat')
    DROP EXTERNAL FILE FORMAT M01ProductMetadataFileFormat;
IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = N'M01ProductMetadataSource')
    DROP EXTERNAL DATA SOURCE M01ProductMetadataSource;
GO

/* ---------------------------------------------------------------------------
   State reset: M01 and every dependent module (M02..M11) become NotStarted.
   * 狀態重設僅影響註解中指定的模組及其相依模組。
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
