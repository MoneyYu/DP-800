/*
    M01 common/02-specialized-tables.sql

    SQL Server 2025 specialized table demonstrations. This asset is invoked
    explicitly until the later documentation task adds it to module-manifest.json.
    It creates only M01-owned objects in AdventureGearAI and never queries
    external data.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* Reapply safely after a prior direct run. The M01 reset owns the full teardown.
*/
/* M08-owned CDC prevents memory-optimized table DDL. Before replacing the M01
   cache, remove only the recorded M08 capture under its lifecycle lock. */
DECLARE @DisableCdcDatabase bit = 0;
DECLARE @M08CaptureInstance sysname;
DECLARE @M08CaptureTableObjectId int;
DECLARE @M08CaptureTableCreatedAt datetime;
DECLARE @ExpectedM08CaptureInstance sysname = N'AdventureGearM08Products';
DECLARE @M08CaptureExists bit = 0;
DECLARE @M08CdcDecommissioned bit = 0;
DECLARE @RemainingCaptureCount int = 0;
DECLARE @CdcOwnershipLockResult int;
DECLARE @CdcOwnershipLockHeld bit = 0;

EXEC @CdcOwnershipLockResult = sys.sp_getapplock
    @Resource = N'DP800.M08.CdcOwnership',
    @LockMode = N'Exclusive',
    @LockOwner = N'Session',
    @LockTimeout = 60000;

IF @CdcOwnershipLockResult < 0
    THROW 51085, 'M01 specialized setup could not acquire the CDC ownership lock.', 1;

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
            SET @M08CdcDecommissioned = 1;

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
        THROW 51086, 'M01 specialized setup cannot replace its memory-optimized table while externally owned CDC remains enabled.', 1;
END TRY
BEGIN CATCH
    IF @CdcOwnershipLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M08.CdcOwnership',
            @LockOwner = N'Session';
    THROW;
END CATCH;

IF OBJECT_ID(N'catalog.ProductCacheInMemory', N'U') IS NOT NULL
    DROP TABLE catalog.ProductCacheInMemory;
IF @CdcOwnershipLockHeld = 1
BEGIN
    EXEC sys.sp_releaseapplock
        @Resource = N'DP800.M08.CdcOwnership',
        @LockOwner = N'Session';
    SET @CdcOwnershipLockHeld = 0;
END;

IF @M08CdcDecommissioned = 1
    UPDATE ops.DemoModuleState
    SET Status = N'NotStarted',
        StartedAtUtc = NULL,
        CompletedAtUtc = NULL,
        LastError = NULL,
        ErrorNumber = NULL,
        ErrorLine = NULL,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE ModuleNumber = 8;

IF OBJECT_ID(N'ops.InventoryLedger', N'U') IS NOT NULL
    DROP TABLE ops.InventoryLedger;
DROP TABLE IF EXISTS catalog.ProductSkuSequenceDemo;
DROP TABLE IF EXISTS catalog.ProductConstraintViolationLog;
DROP TABLE IF EXISTS catalog.ProductConstraintChild;
DROP TABLE IF EXISTS catalog.ProductConstraintParent;
IF OBJECT_ID(N'catalog.ProductSkuSequence', N'SO') IS NOT NULL
    DROP SEQUENCE catalog.ProductSkuSequence;

IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'catalog.ProductMetadataExternal'))
    DROP EXTERNAL TABLE catalog.ProductMetadataExternal;
IF EXISTS (SELECT 1 FROM sys.external_file_formats WHERE name = N'M01ProductMetadataFileFormat')
    DROP EXTERNAL FILE FORMAT M01ProductMetadataFileFormat;
IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = N'M01ProductMetadataSource')
    DROP EXTERNAL DATA SOURCE M01ProductMetadataSource;
GO

/* ---------------------------------------------------------------------------
   1) In-Memory OLTP. The memory-optimized filegroup is created only where the
      engine supports XTP. The filegroup/file are intentionally retained by
      reset because removing an XTP container can hang in observed containers.
--------------------------------------------------------------------------- */
IF CONVERT(int, SERVERPROPERTY('IsXTPSupported')) = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.filegroups WHERE name = N'M01MemoryOptimized')
    BEGIN
        ALTER DATABASE CURRENT ADD FILEGROUP M01MemoryOptimized CONTAINS MEMORY_OPTIMIZED_DATA;

        DECLARE @xtpDirectory nvarchar(260) = CONVERT(nvarchar(260), SERVERPROPERTY('InstanceDefaultDataPath'));
        DECLARE @xtpFile nvarchar(4000) = CONCAT(
            CASE WHEN RIGHT(@xtpDirectory, 1) IN (N'\', N'/') THEN @xtpDirectory ELSE CONCAT(@xtpDirectory, N'/') END,
            DB_NAME(), N'_M01MemoryOptimized');
        DECLARE @addFile nvarchar(max) = N'ALTER DATABASE CURRENT ADD FILE
            (NAME = N''M01MemoryOptimizedFile'', FILENAME = N''' + REPLACE(@xtpFile, N'''', N'''''') + N''')
            TO FILEGROUP M01MemoryOptimized;';
        EXEC sys.sp_executesql @addFile;
    END;

    CREATE TABLE catalog.ProductCacheInMemory
    (
        ProductID int NOT NULL
            CONSTRAINT PK_ProductCacheInMemory PRIMARY KEY NONCLUSTERED,
        ProductName nvarchar(120) NOT NULL,
        CachedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_ProductCacheInMemory_CachedAtUtc DEFAULT SYSUTCDATETIME()
    )
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

    INSERT catalog.ProductCacheInMemory (ProductID, ProductName)
    SELECT ProductID, ProductName
    FROM catalog.Products
    WHERE ProductID IN (1, 2);

    PRINT N'M01 In-Memory OLTP cache created.';
END;
ELSE
    PRINT N'M01 In-Memory OLTP skipped: SERVERPROPERTY(''IsXTPSupported'') is not 1.';
GO

/* ---------------------------------------------------------------------------
   2) Updatable ledger table. SQL Server generates and manages its ledger
      history table and ledger view; the local inspection script exposes both.
--------------------------------------------------------------------------- */
CREATE TABLE ops.InventoryLedger
(
    InventoryLedgerID int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ProductID int NOT NULL REFERENCES catalog.Products(ProductID),
    QuantityDelta int NOT NULL,
    RecordedAtUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME()
)
WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);

INSERT ops.InventoryLedger (ProductID, QuantityDelta)
VALUES (1, 2), (2, -1);
GO

/* ---------------------------------------------------------------------------
   3) Sequence allocation. The selected values are stored in an M01-owned
      result table so the inspection and runtime tests can demonstrate them.
--------------------------------------------------------------------------- */
CREATE SEQUENCE catalog.ProductSkuSequence
    AS int
    START WITH 1000
    INCREMENT BY 10;
GO

CREATE TABLE catalog.ProductSkuSequenceDemo
(
    ProductSkuSequenceDemoID int NOT NULL
        CONSTRAINT PK_ProductSkuSequenceDemo PRIMARY KEY,
    AllocatedSkuNumber int NOT NULL
        CONSTRAINT UQ_ProductSkuSequenceDemo_AllocatedSkuNumber UNIQUE
);

INSERT catalog.ProductSkuSequenceDemo (ProductSkuSequenceDemoID, AllocatedSkuNumber)
VALUES
    (1, NEXT VALUE FOR catalog.ProductSkuSequence),
    (2, NEXT VALUE FOR catalog.ProductSkuSequence);
GO

/* ---------------------------------------------------------------------------
   4) Constraints. Each intentional violation is caught and recorded, leaving
      only valid rows. This demonstrates PK, FK, UNIQUE, CHECK, and DEFAULT.
--------------------------------------------------------------------------- */
CREATE TABLE catalog.ProductConstraintParent
(
    ProductConstraintParentID int NOT NULL
        CONSTRAINT PK_ProductConstraintParent PRIMARY KEY,
    ConstraintCode nvarchar(30) NOT NULL
        CONSTRAINT UQ_ProductConstraintParent_ConstraintCode UNIQUE,
    MinimumQuantity int NOT NULL
        CONSTRAINT CK_ProductConstraintParent_MinimumQuantity CHECK (MinimumQuantity >= 0),
    IsEnabled bit NOT NULL
        CONSTRAINT DF_ProductConstraintParent_IsEnabled DEFAULT 1
);

CREATE TABLE catalog.ProductConstraintChild
(
    ProductConstraintChildID int NOT NULL
        CONSTRAINT PK_ProductConstraintChild PRIMARY KEY,
    ProductConstraintParentID int NOT NULL
        CONSTRAINT FK_ProductConstraintChild_Parent
            REFERENCES catalog.ProductConstraintParent(ProductConstraintParentID)
);

CREATE TABLE catalog.ProductConstraintViolationLog
(
    ProductConstraintViolationLogID int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_ProductConstraintViolationLog PRIMARY KEY,
    ConstraintLesson nvarchar(20) NOT NULL,
    ErrorNumber int NOT NULL,
    ErrorMessage nvarchar(2048) NOT NULL
);

INSERT catalog.ProductConstraintParent
    (ProductConstraintParentID, ConstraintCode, MinimumQuantity)
VALUES (1, N'M01-VALID', 5);
INSERT catalog.ProductConstraintChild (ProductConstraintChildID, ProductConstraintParentID)
VALUES (1, 1);

SELECT ProductConstraintParentID,
       ConstraintCode,
       MinimumQuantity,
       IsEnabled AS DefaultApplied
FROM catalog.ProductConstraintParent
WHERE ProductConstraintParentID = 1;

BEGIN TRY
    INSERT catalog.ProductConstraintParent (ProductConstraintParentID, ConstraintCode, MinimumQuantity)
    VALUES (1, N'M01-DUPLICATE-PK', 1);
END TRY
BEGIN CATCH
    INSERT catalog.ProductConstraintViolationLog (ConstraintLesson, ErrorNumber, ErrorMessage)
    VALUES (N'PRIMARY KEY', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT catalog.ProductConstraintParent (ProductConstraintParentID, ConstraintCode, MinimumQuantity)
    VALUES (2, N'M01-VALID', 1);
END TRY
BEGIN CATCH
    INSERT catalog.ProductConstraintViolationLog (ConstraintLesson, ErrorNumber, ErrorMessage)
    VALUES (N'UNIQUE', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT catalog.ProductConstraintParent (ProductConstraintParentID, ConstraintCode, MinimumQuantity)
    VALUES (3, N'M01-CHECK', -1);
END TRY
BEGIN CATCH
    INSERT catalog.ProductConstraintViolationLog (ConstraintLesson, ErrorNumber, ErrorMessage)
    VALUES (N'CHECK', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT catalog.ProductConstraintChild (ProductConstraintChildID, ProductConstraintParentID)
    VALUES (2, 999);
END TRY
BEGIN CATCH
    INSERT catalog.ProductConstraintViolationLog (ConstraintLesson, ErrorNumber, ErrorMessage)
    VALUES (N'FOREIGN KEY', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;
GO

/* ---------------------------------------------------------------------------
   5) PolyBase external metadata. It is intentionally metadata-only: no
      credentials, external data creation, or SELECT from the external table.
--------------------------------------------------------------------------- */
IF CONVERT(int, SERVERPROPERTY('IsPolyBaseInstalled')) = 1
BEGIN
    CREATE EXTERNAL DATA SOURCE M01ProductMetadataSource
    WITH (LOCATION = 'abs://public@azureopendatastorage.blob.core.windows.net');

    CREATE EXTERNAL FILE FORMAT M01ProductMetadataFileFormat
    WITH
    (
        FORMAT_TYPE = DELIMITEDTEXT,
        FORMAT_OPTIONS (FIELD_TERMINATOR = N',')
    );

    CREATE EXTERNAL TABLE catalog.ProductMetadataExternal
    (
        ProductID int,
        ProductName nvarchar(120),
        Metadata nvarchar(4000)
    )
    WITH
    (
        LOCATION = '/m01-metadata-only/no-query.csv',
        DATA_SOURCE = M01ProductMetadataSource,
        FILE_FORMAT = M01ProductMetadataFileFormat
    );

    PRINT N'M01 PolyBase external metadata created; no external data query was executed.';
END;
ELSE
    PRINT N'M01 PolyBase external table skipped: SERVERPROPERTY(''IsPolyBaseInstalled'') is not 1.';
GO

PRINT N'M01 specialized tables created against AdventureGearAI.';
GO
