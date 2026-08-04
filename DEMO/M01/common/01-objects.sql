/*
    M01 common/01-objects.sql

    Module 1 (Design and implement database objects) extensions for the unified
    AdventureGearAI demo. These objects EXTEND the canonical core created by the
    bootstrap (catalog.Products / catalog.Categories / sales.Orders / ...). They
    do NOT recreate the core commerce entities.

    Objects provisioned here:
      * catalog.ProductPrice + catalog.ProductPriceHistory  (system-versioned temporal)
      * catalog.Products.MetadataFrame                       (computed JSON projection + index)
      * catalog.Products.ProductMetadata                     (native json predicates + JSON index)
      * catalog.ProductJsonTeaching                          (safe native json .modify() exercise)
      * sales.PartitionedOrders                              (range-partitioned teaching object)
      * catalog.ProductNode / catalog.ProductRelatedTo       (SQL graph node/edge)

    The script is idempotent: every module-owned object is dropped (guarded) and
    recreated so the module can be re-run through the runner with -Force.
    * 模組 1 的統一 AdventureGearAI 示範延伸物件：擴充 bootstrap 建立的標準核心，而不重建商務實體；建立時態價格、JSON 投影及索引、範圍分割訂單與 SQL 圖形。指令碼可等冪地以 -Force 重跑。
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

/* Share a lifecycle lock with reset. The runner keeps Module 1 in Running
   state across its separate setup scripts; this lock also protects direct
   execution of this script from a concurrent scoped reset. */
DECLARE @M01LifecycleLockResult int;
EXEC @M01LifecycleLockResult = sys.sp_getapplock
    @Resource = N'DP800.M01.Lifecycle',
    @LockMode = N'Exclusive',
    @LockOwner = N'Session',
    @LockTimeout = 60000;

IF @M01LifecycleLockResult < 0
    THROW 51087, 'M01 object setup could not acquire the module lifecycle lock.', 1;
GO

/* ---------------------------------------------------------------------------
   Idempotent teardown of module-owned objects (never the canonical core).
   * 以等冪方式只清除本模組物件，絕不清除標準核心。
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

IF EXISTS (SELECT 1 FROM sys.json_indexes WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'IX_Products_ProductMetadata')
    DROP INDEX IX_Products_ProductMetadata ON catalog.Products;
DROP TABLE IF EXISTS catalog.ProductJsonTeaching;
GO

/* ---------------------------------------------------------------------------
   1) System-versioned temporal price table sourced from canonical products.
   * 從標準產品建立系統版本控制的時態價格資料表。
--------------------------------------------------------------------------- */
CREATE TABLE catalog.ProductPrice
(
    ProductID int NOT NULL CONSTRAINT PK_ProductPrice PRIMARY KEY
        CONSTRAINT FK_ProductPrice_Products REFERENCES catalog.Products(ProductID),
    CurrentPrice decimal(10,2) NOT NULL
        CONSTRAINT CK_ProductPrice_CurrentPrice CHECK (CurrentPrice > 0),
    ValidFrom datetime2(7) GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo datetime2(7) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH
(
    SYSTEM_VERSIONING = ON
    (
        HISTORY_TABLE = catalog.ProductPriceHistory,
        DATA_CONSISTENCY_CHECK = ON
    )
);

INSERT catalog.ProductPrice (ProductID, CurrentPrice)
SELECT ProductID, UnitPrice FROM catalog.Products;

/* Generate a history row so FOR SYSTEM_TIME ALL returns more than one version.
    * 建立歷程資料列，使 FOR SYSTEM_TIME ALL 傳回多個版本。
*/
UPDATE catalog.ProductPrice
SET CurrentPrice = CurrentPrice * 0.95
WHERE ProductID = 1;
GO

/* ---------------------------------------------------------------------------
   2) Indexed computed JSON projection over the canonical ProductMetadata.
   * 在標準 ProductMetadata 上建立已建立索引的計算式 JSON 投影。
--------------------------------------------------------------------------- */
ALTER TABLE catalog.Products
ADD MetadataFrame AS CONVERT(nvarchar(50), JSON_VALUE(ProductMetadata, '$.frame'));
GO

CREATE INDEX IX_Products_MetadataFrame
ON catalog.Products(MetadataFrame);
GO

/* Native json predicates operate on the canonical json column. The JSON index
   below is supported because ProductMetadata is native json and PK_Products is
   the table's clustered primary key. The SET options at the top of this script
   are required for deterministic indexed-object creation.
   * 原生 json 述詞直接操作標準 ProductMetadata；JSON 索引使用原生 json 欄位與
     clustered PK。指令碼開頭的 SET 選項確保建立索引物件時的設定正確。
*/
SELECT ProductID,
       ProductName,
       JSON_VALUE(ProductMetadata, '$.frame') AS FrameMaterial,
       JSON_PATH_EXISTS(ProductMetadata, '$.frame') AS HasFrame,
       JSON_CONTAINS(ProductMetadata, N'aluminum', '$.frame') AS IsAluminumFrame
FROM catalog.Products
WHERE ProductID = 1;
GO

CREATE JSON INDEX IX_Products_ProductMetadata
ON catalog.Products(ProductMetadata)
WITH (OPTIMIZE_FOR_ARRAY_SEARCH = ON);
GO

/* The .modify() method changes only a module-owned teaching row, so
   catalog.Products remains canonical. Reset drops this teaching table.
   * .modify() 只變更模組擁有的教學資料列；標準產品資料保持不變，reset 會移除此表。
*/
CREATE TABLE catalog.ProductJsonTeaching
(
    ProductJsonTeachingID int NOT NULL
        CONSTRAINT PK_ProductJsonTeaching PRIMARY KEY CLUSTERED,
    Payload json NOT NULL
);

INSERT catalog.ProductJsonTeaching (ProductJsonTeachingID, Payload)
VALUES (1, N'{"lesson":"M01-safe-original","topic":"native json"}');

UPDATE catalog.ProductJsonTeaching
SET Payload.modify('$.lesson', N'M01-safe-modified')
WHERE ProductJsonTeachingID = 1;

SELECT JSON_VALUE(Payload, '$.lesson') AS ModifiedLesson
FROM catalog.ProductJsonTeaching
WHERE ProductJsonTeachingID = 1;
GO

/* ---------------------------------------------------------------------------
   3) Range-partitioned order teaching object (separate from canonical orders).
      Seeded with realistic customer names across 2026 quarters so the partition
      distribution is visible.
   * 建立與標準訂單分離的範圍分割教學物件，並以 2026 年各季資料植入以顯示分割分布。
--------------------------------------------------------------------------- */
CREATE PARTITION FUNCTION PF_AdventureGear_OrderDate(date)
AS RANGE RIGHT FOR VALUES ('2026-01-01', '2026-04-01', '2026-07-01', '2026-10-01');

CREATE PARTITION SCHEME PS_AdventureGear_OrderDate
AS PARTITION PF_AdventureGear_OrderDate ALL TO ([PRIMARY]);

CREATE TABLE sales.PartitionedOrders
(
    PartitionedOrderID bigint IDENTITY(1,1) NOT NULL,
    OrderDate date NOT NULL,
    CustomerName nvarchar(120) NOT NULL,
    TotalAmount decimal(12,2) NOT NULL,
    CONSTRAINT PK_PartitionedOrders PRIMARY KEY (PartitionedOrderID, OrderDate)
) ON PS_AdventureGear_OrderDate(OrderDate);

INSERT sales.PartitionedOrders (OrderDate, CustomerName, TotalAmount) VALUES
    ('2025-12-20', N'Devon Brooks', 4798.00),
    ('2026-01-15', N'Avery Chen', 1543.90),
    ('2026-05-12', N'Morgan Lee', 125.00),
    ('2026-08-03', N'Jordan Patel', 368.00),
    ('2026-11-20', N'Riley Nguyen', 237.00);
GO

/* ---------------------------------------------------------------------------
   4) SQL graph node/edge modelling product complements.
   * 以 SQL 圖形節點與邊模擬產品互補關係。
--------------------------------------------------------------------------- */
CREATE TABLE catalog.ProductNode
(
    ProductID int NOT NULL,
    ProductName nvarchar(120) NOT NULL
) AS NODE;

CREATE TABLE catalog.ProductRelatedTo
(
    RelationshipType nvarchar(30) NOT NULL
) AS EDGE;

INSERT catalog.ProductNode (ProductID, ProductName)
SELECT ProductID, ProductName FROM catalog.Products;

/* The Trailblazer 29 bike (ProductID 1) complements a tire, a light, and a pack.
    * Trailblazer 29 自行車（ProductID 1）與輪胎、車燈及背包互補。
*/
INSERT catalog.ProductRelatedTo ($from_id, $to_id, RelationshipType)
SELECT sourceNode.$node_id, targetNode.$node_id, N'complements'
FROM catalog.ProductNode AS sourceNode
CROSS JOIN catalog.ProductNode AS targetNode
WHERE sourceNode.ProductID = 1 AND targetNode.ProductID IN (4, 7, 8);
GO

PRINT N'M01 objects created against AdventureGearAI (catalog/sales extensions).';
GO

EXEC sys.sp_releaseapplock
    @Resource = N'DP800.M01.Lifecycle',
    @LockOwner = N'Session';
GO
