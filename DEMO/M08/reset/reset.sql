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
    M08 reset/reset.sql
    統一 AdventureGearAI 示範的模組範圍重設。它絕不卸除資料庫；只移除模組 8 的 API 投影檢視表，並將模組 8 還原為 NotStarted 基準狀態。檢視表投影的標準 catalog 核心會保持不變。
    移除的模組專屬物件：api.InventoryAvailability、api.ProductCatalog、api.Products、api.Categories（皆為檢視表）。
    M08 沒有下游模組相依項，因此只會重設 M08。
    設計為透過 DEMO/scripts/Invoke-Dp800Sql.ps1 對 AdventureGearAI 執行；該工具會先執行唯讀 Assert-DemoDatabase.sql 防護。下方內嵌防護可為直接執行提供縱深防禦。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Guard 1: refuse to run against anything but AdventureGearAI.
   防護 1：拒絕在 AdventureGearAI 以外的任何資料庫執行。
   */
IF DB_NAME() <> N'AdventureGearAI'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'M08 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
   防護 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
   */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M08 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown CDC objects owned by M08, then module-owned API views, procedure,
   and CDC status. The canonical catalog core is never dropped.
---------------------------------------------------------------------------
只拆除模組專屬檢視表。標準 catalog 核心絕不會被卸除。
*/
DECLARE @DisableCdcDatabase bit = 0;
DECLARE @M08CaptureInstance sysname;
DECLARE @M08CaptureTableObjectId int;
DECLARE @M08CaptureTableCreatedAt datetime;
DECLARE @ExpectedM08CaptureInstance sysname = N'AdventureGearM08Products';
DECLARE @M08CaptureExists bit = 0;
DECLARE @RemainingCaptureCount int = 0;
DECLARE @AppLockResult int;

EXEC @AppLockResult = sys.sp_getapplock
    @Resource = N'DP800.M08.CdcOwnership',
    @LockMode = N'Exclusive',
    @LockOwner = N'Session',
    @LockTimeout = 60000;

IF @AppLockResult < 0
    THROW 51081, 'M08 reset could not acquire the CDC ownership lock.', 1;

BEGIN TRY
    /* The application lock protects this revalidation-and-disable sequence from
       concurrent M08 setup/reset runs. Do not infer ownership from the source
       table: only the recorded dedicated capture identity is removable. */
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
        /* cdc.change_tables does not exist when database CDC is disabled. Query it
           dynamically only after the database-level guard has succeeded. */
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
END TRY
BEGIN CATCH
    EXEC sys.sp_releaseapplock
        @Resource = N'DP800.M08.CdcOwnership',
        @LockOwner = N'Session';
    THROW;
END CATCH;

EXEC sys.sp_releaseapplock
    @Resource = N'DP800.M08.CdcOwnership',
    @LockOwner = N'Session';
GO

DROP PROCEDURE IF EXISTS api.GetProductsByCategory;
DROP VIEW IF EXISTS api.InventoryAvailability;
DROP VIEW IF EXISTS api.ProductCatalog;
DROP VIEW IF EXISTS api.Products;
DROP VIEW IF EXISTS api.Categories;
DROP TABLE IF EXISTS api.CdcRuntimeStatus;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 8 (no dependents).
---------------------------------------------------------------------------
狀態重設：只重設模組 8（沒有相依項）。
*/
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
PRINT N'M08 reset complete: M08 CDC capture, api.* projection views, and procedure removed; M08 marked NotStarted.';
GO
