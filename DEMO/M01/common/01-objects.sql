/*
    M01 common/01-objects.sql

    Module 1 (Design and implement database objects) extensions for the unified
    AdventureGearAI demo. These objects EXTEND the canonical core created by the
    bootstrap (catalog.Products / catalog.Categories / sales.Orders / ...). They
    do NOT recreate the core commerce entities.

    Objects provisioned here:
      * catalog.ProductPrice + catalog.ProductPriceHistory  (system-versioned temporal)
      * catalog.Products.MetadataFrame                       (computed JSON projection + index)
      * sales.PartitionedOrders                              (range-partitioned teaching object)
      * catalog.ProductNode / catalog.ProductRelatedTo       (SQL graph node/edge)

    The script is idempotent: every module-owned object is dropped (guarded) and
    recreated so the module can be re-run through the runner with -Force.
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

/* ---------------------------------------------------------------------------
   Idempotent teardown of module-owned objects (never the canonical core).
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
   1) System-versioned temporal price table sourced from canonical products.
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

/* Generate a history row so FOR SYSTEM_TIME ALL returns more than one version. */
UPDATE catalog.ProductPrice
SET CurrentPrice = CurrentPrice * 0.95
WHERE ProductID = 1;
GO

/* ---------------------------------------------------------------------------
   2) Indexed computed JSON projection over the canonical ProductMetadata.
--------------------------------------------------------------------------- */
ALTER TABLE catalog.Products
ADD MetadataFrame AS CONVERT(nvarchar(50), JSON_VALUE(ProductMetadata, '$.frame'));
GO

CREATE INDEX IX_Products_MetadataFrame
ON catalog.Products(MetadataFrame);
GO

/* ---------------------------------------------------------------------------
   3) Range-partitioned order teaching object (separate from canonical orders).
      Seeded with realistic customer names across 2026 quarters so the partition
      distribution is visible.
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

/* The Trailblazer 29 bike (ProductID 1) complements a tire, a light, and a pack. */
INSERT catalog.ProductRelatedTo ($from_id, $to_id, RelationshipType)
SELECT sourceNode.$node_id, targetNode.$node_id, N'complements'
FROM catalog.ProductNode AS sourceNode
CROSS JOIN catalog.ProductNode AS targetNode
WHERE sourceNode.ProductID = 1 AND targetNode.ProductID IN (4, 7, 8);
GO

PRINT N'M01 objects created against AdventureGearAI (catalog/sales extensions).';
GO
