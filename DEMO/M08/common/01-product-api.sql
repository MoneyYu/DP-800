/*
    M08 common setup — REST/GraphQL API surface for AdventureGearAI.

    Instead of creating duplicate ApiProducts/ApiCategories tables, this script
    projects the canonical AdventureGearAI domain data through read-only views in
    the api schema. The DAB Category/Product entities use the canonical catalog
    tables so the CLI can validate their relationships; these api views remain
    available to the SQL demos. The api schema is created by the core bootstrap;
    this script is idempotent and safe to re-run.
    M08 共用設定：AdventureGearAI 的 REST/GraphQL API 介面。
    此指令碼不會建立重複的 ApiProducts/ApiCategories 資料表，而是在 api 結構描述中的唯讀檢視表投影標準 AdventureGearAI 網域資料。DAB Category/Product entity 會使用正規 catalog 資料表，讓 CLI 可驗證其 relationships；這些 api 檢視表仍供 SQL demo 使用。api 結構描述由核心 bootstrap 建立；此指令碼具冪等性，且可安全地重新執行。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

DECLARE @engineEdition int = CONVERT(int, SERVERPROPERTY('EngineEdition'));
DECLARE @sqlAgentAvailable bit = 0;
DECLARE @databaseCdcEnabledByModule bit = 0;
DECLARE @productCaptureEnabled bit = 0;
DECLARE @m08CaptureInstance sysname = N'AdventureGearM08Products';
DECLARE @m08CaptureTableObjectId int;
DECLARE @m08CaptureTableCreatedAt datetime;
DECLARE @recordedM08CaptureInstance sysname;
DECLARE @recordedM08CaptureTableObjectId int;
DECLARE @recordedM08CaptureTableCreatedAt datetime;
DECLARE @behavior nvarchar(1000);
DECLARE @appLockResult int;
DECLARE @appLockHeld bit = 0;

BEGIN TRY
    EXEC @appLockResult = sys.sp_getapplock
        @Resource = N'DP800.M08.CdcOwnership',
        @LockMode = N'Exclusive',
        @LockOwner = N'Session',
        @LockTimeout = 60000;

    IF @appLockResult < 0
        THROW 51080, 'M08 could not acquire the CDC ownership lock.', 1;

    SET @appLockHeld = 1;

    /* Remove any legacy duplicate API tables/views from earlier per-module demos.
       Keep this under the M08 lifecycle lock with every owned API DDL operation. */
    DROP VIEW IF EXISTS dbo.ProductCatalogView;
    DROP TABLE IF EXISTS dbo.ApiProducts;
    DROP TABLE IF EXISTS dbo.ApiCategories;

    IF OBJECT_ID(N'api.CdcRuntimeStatus', N'U') IS NULL
    BEGIN
        CREATE TABLE api.CdcRuntimeStatus
        (
            CdcRuntimeStatusID tinyint NOT NULL
                CONSTRAINT PK_CdcRuntimeStatus PRIMARY KEY
                CONSTRAINT CK_CdcRuntimeStatus_Singleton CHECK (CdcRuntimeStatusID = 1),
            RecordedAtUtc datetime2(0) NOT NULL,
            EngineEdition int NOT NULL,
            SqlAgentAvailable bit NOT NULL,
            DatabaseCdcEnabledByModule bit NOT NULL,
            ProductCaptureEnabled bit NOT NULL,
            M08CaptureInstance sysname NULL,
            M08CaptureTableObjectId int NULL,
            M08CaptureTableCreatedAt datetime NULL,
            Behavior nvarchar(1000) NOT NULL
        );
    END;

    IF COL_LENGTH(N'api.CdcRuntimeStatus', N'M08CaptureInstance') IS NULL
        ALTER TABLE api.CdcRuntimeStatus ADD M08CaptureInstance sysname NULL;
    IF COL_LENGTH(N'api.CdcRuntimeStatus', N'M08CaptureTableObjectId') IS NULL
        ALTER TABLE api.CdcRuntimeStatus ADD M08CaptureTableObjectId int NULL;
    IF COL_LENGTH(N'api.CdcRuntimeStatus', N'M08CaptureTableCreatedAt') IS NULL
        ALTER TABLE api.CdcRuntimeStatus ADD M08CaptureTableCreatedAt datetime NULL;

    /* Preserve the ownership marker across idempotent re-runs. Without it, a
       second run would forget that M08, rather than a pre-existing feature,
       enabled CDC at database scope. */
    SELECT @databaseCdcEnabledByModule = DatabaseCdcEnabledByModule
    FROM api.CdcRuntimeStatus
    WHERE CdcRuntimeStatusID = 1;
    SELECT
        @recordedM08CaptureInstance = M08CaptureInstance,
        @recordedM08CaptureTableObjectId = M08CaptureTableObjectId,
        @recordedM08CaptureTableCreatedAt = M08CaptureTableCreatedAt
    FROM api.CdcRuntimeStatus
    WHERE CdcRuntimeStatusID = 1;

    /* Azure SQL Database manages CDC capture. Local SQL Server needs a running
       SQL Server Agent for capture/cleanup jobs; record that actual boundary. */
    IF @engineEdition = 5
        SET @sqlAgentAvailable = 1;
    ELSE
    BEGIN
        BEGIN TRY
            IF EXISTS
            (
                SELECT 1
                FROM sys.dm_server_services
                WHERE servicename LIKE N'SQL Server Agent%'
                  AND status_desc = N'Running'
            )
                SET @sqlAgentAvailable = 1;
        END TRY
        BEGIN CATCH
            SET @sqlAgentAvailable = 0;
        END CATCH;
    END;

    BEGIN TRY
    IF (SELECT is_cdc_enabled FROM sys.databases WHERE database_id = DB_ID()) = 0
    BEGIN
        EXEC sys.sp_cdc_enable_db;
        SET @databaseCdcEnabledByModule = 1;
    END;

    /* A capture is M08-owned only when its prior exact identity was recorded.
       Never adopt a pre-existing capture, even if it uses M08's dedicated name. */
    IF @recordedM08CaptureInstance = @m08CaptureInstance
       AND EXISTS
       (
           SELECT 1
           FROM cdc.change_tables AS ct
           INNER JOIN sys.objects AS cdcTable
               ON cdcTable.object_id = OBJECT_ID(N'cdc.' + ct.capture_instance + N'_CT')
           WHERE ct.source_object_id = OBJECT_ID(N'catalog.Products')
             AND ct.capture_instance = @m08CaptureInstance
             AND cdcTable.object_id = @recordedM08CaptureTableObjectId
             AND cdcTable.create_date = @recordedM08CaptureTableCreatedAt
       )
    BEGIN
        SET @m08CaptureTableObjectId = @recordedM08CaptureTableObjectId;
        SET @m08CaptureTableCreatedAt = @recordedM08CaptureTableCreatedAt;
    END
    ELSE
    BEGIN
        SET @m08CaptureTableObjectId = NULL;
        SET @m08CaptureTableCreatedAt = NULL;
    END;

    IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
       AND NOT EXISTS
       (
           SELECT 1
           FROM cdc.change_tables
           WHERE source_object_id = OBJECT_ID(N'catalog.Products')
             AND capture_instance = @m08CaptureInstance
       )
    BEGIN
        EXEC sys.sp_cdc_enable_table
            @source_schema = N'catalog',
            @source_name = N'Products',
            @role_name = NULL,
            @supports_net_changes = 1,
            @capture_instance = @m08CaptureInstance;

        SELECT
            @m08CaptureTableObjectId = cdcTable.object_id,
            @m08CaptureTableCreatedAt = cdcTable.create_date
        FROM cdc.change_tables AS ct
        INNER JOIN sys.objects AS cdcTable
            ON cdcTable.object_id = OBJECT_ID(N'cdc.' + ct.capture_instance + N'_CT')
        WHERE ct.source_object_id = OBJECT_ID(N'catalog.Products')
          AND ct.capture_instance = @m08CaptureInstance;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM cdc.change_tables
        WHERE source_object_id = OBJECT_ID(N'catalog.Products')
          AND capture_instance = @m08CaptureInstance
    )
        SET @productCaptureEnabled = 1;

    SET @behavior =
        CASE
            WHEN @productCaptureEnabled = 0 THEN N'M08 did not enable its dedicated CDC capture for catalog.Products.'
            WHEN @engineEdition = 5 THEN N'Azure SQL Database manages CDC capture; no SQL Server Agent service is expected.'
            WHEN @sqlAgentAvailable = 1 THEN N'CDC capture is enabled and SQL Server Agent is running.'
            ELSE N'CDC metadata is enabled, but local capture/cleanup jobs wait until SQL Server Agent is available.'
        END;
    END TRY
    BEGIN CATCH
        SET @m08CaptureTableObjectId = NULL;
        SET @m08CaptureTableCreatedAt = NULL;
        SET @productCaptureEnabled = 0;
        SET @behavior = CONCAT(N'CDC enablement was skipped: ', ERROR_MESSAGE());
    END CATCH;

    DELETE FROM api.CdcRuntimeStatus;
    INSERT api.CdcRuntimeStatus
    (
        CdcRuntimeStatusID,
        RecordedAtUtc,
        EngineEdition,
        SqlAgentAvailable,
        DatabaseCdcEnabledByModule,
        ProductCaptureEnabled,
        M08CaptureInstance,
        M08CaptureTableObjectId,
        M08CaptureTableCreatedAt,
        Behavior
    )
    VALUES
    (
        1,
        SYSUTCDATETIME(),
        @engineEdition,
        @sqlAgentAvailable,
        @databaseCdcEnabledByModule,
        @productCaptureEnabled,
        CASE WHEN @productCaptureEnabled = 1 THEN @m08CaptureInstance END,
        @m08CaptureTableObjectId,
        @m08CaptureTableCreatedAt,
        @behavior
    );

    SELECT
        RecordedAtUtc,
        EngineEdition,
        SqlAgentAvailable,
        DatabaseCdcEnabledByModule,
        ProductCaptureEnabled,
        M08CaptureInstance,
        M08CaptureTableObjectId,
        M08CaptureTableCreatedAt,
        Behavior
    FROM api.CdcRuntimeStatus;

    /* CREATE OR ALTER VIEW/PROCEDURE must be the first statement in their own
       batches. Execute them dynamically so the same TRY/CATCH owns both their
       failure path and the session applock. */
    EXEC sys.sp_executesql N'
CREATE OR ALTER VIEW api.Categories
AS
SELECT
    c.CategoryID,
    c.CategoryName,
    c.Description,
    c.IsActive
FROM catalog.Categories AS c;';

    EXEC sys.sp_executesql N'
CREATE OR ALTER VIEW api.Products
AS
SELECT
    p.ProductID,
    p.ProductName,
    p.CategoryID,
    p.Sku,
    p.UnitPrice,
    COALESCE(i.QuantityOnHand, 0) AS UnitsInStock,
    p.IsActive
FROM catalog.Products AS p
LEFT JOIN catalog.Inventory AS i ON i.ProductID = p.ProductID;';

    EXEC sys.sp_executesql N'
CREATE OR ALTER VIEW api.ProductCatalog
AS
SELECT
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    p.UnitPrice,
    COALESCE(i.QuantityOnHand, 0) AS UnitsInStock,
    CASE
        WHEN COALESCE(i.QuantityOnHand, 0) = 0 THEN N''Out of stock''
        WHEN i.QuantityOnHand < i.ReorderThreshold THEN N''Low stock''
        ELSE N''Available''
    END AS StockStatus
FROM catalog.Products AS p
INNER JOIN catalog.Categories AS c ON c.CategoryID = p.CategoryID
LEFT JOIN catalog.Inventory AS i ON i.ProductID = p.ProductID
WHERE p.IsActive = 1;';

    EXEC sys.sp_executesql N'
CREATE OR ALTER VIEW api.InventoryAvailability
AS
SELECT
    i.ProductID,
    p.ProductName,
    i.QuantityOnHand,
    i.ReorderThreshold,
    i.WarehouseLocation,
    CASE
        WHEN i.QuantityOnHand = 0 THEN N''Out of stock''
        WHEN i.QuantityOnHand < i.ReorderThreshold THEN N''Reorder''
        ELSE N''In stock''
    END AS AvailabilityStatus
FROM catalog.Inventory AS i
INNER JOIN catalog.Products AS p ON p.ProductID = i.ProductID;';

    EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE api.GetProductsByCategory
    @CategoryID int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ProductID,
        ProductName,
        CategoryID,
        Sku,
        UnitPrice,
        UnitsInStock,
        IsActive
    FROM api.Products
    WHERE @CategoryID IS NULL OR CategoryID = @CategoryID
    ORDER BY ProductID;
END;';

    EXEC sys.sp_releaseapplock
        @Resource = N'DP800.M08.CdcOwnership',
        @LockOwner = N'Session';
    SET @appLockHeld = 0;
END TRY
BEGIN CATCH
    IF @appLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M08.CdcOwnership',
            @LockOwner = N'Session';
    THROW;
END CATCH;
GO

PRINT N'M08 api.* views, CDC status, and safe product procedure are ready.';
GO
