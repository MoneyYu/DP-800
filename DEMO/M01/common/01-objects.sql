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

IF OBJECT_ID(N'dbo.ProductRelatedTo', N'U') IS NOT NULL DROP TABLE dbo.ProductRelatedTo;
IF OBJECT_ID(N'dbo.ProductNode', N'U') IS NOT NULL DROP TABLE dbo.ProductNode;

IF OBJECT_ID(N'dbo.ProductPrice', N'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.ProductPrice SET (SYSTEM_VERSIONING = OFF);
    DROP TABLE dbo.ProductPrice;
END;
DROP TABLE IF EXISTS dbo.ProductPriceHistory;
DROP TABLE IF EXISTS dbo.PartitionedOrders;
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'PS_DP800_OrderDate')
    DROP PARTITION SCHEME PS_DP800_OrderDate;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'PF_DP800_OrderDate')
    DROP PARTITION FUNCTION PF_DP800_OrderDate;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Products') AND name = N'IX_Products_MetadataColor')
    DROP INDEX IX_Products_MetadataColor ON dbo.Products;
IF COL_LENGTH(N'dbo.Products', N'MetadataColor') IS NOT NULL
    ALTER TABLE dbo.Products DROP COLUMN MetadataColor;
GO

CREATE TABLE dbo.ProductPrice
(
    ProductID int NOT NULL CONSTRAINT PK_ProductPrice PRIMARY KEY
        CONSTRAINT FK_ProductPrice_Products REFERENCES dbo.Products(ProductID),
    CurrentPrice decimal(10,2) NOT NULL,
    ValidFrom datetime2(7) GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo datetime2(7) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH
(
    SYSTEM_VERSIONING = ON
    (
        HISTORY_TABLE = dbo.ProductPriceHistory,
        DATA_CONSISTENCY_CHECK = ON
    )
);

INSERT dbo.ProductPrice (ProductID, CurrentPrice)
SELECT ProductID, UnitPrice FROM dbo.Products;

UPDATE dbo.ProductPrice
SET CurrentPrice = CurrentPrice * 0.95
WHERE ProductID = 1;

ALTER TABLE dbo.Products
ADD MetadataColor AS CONVERT(nvarchar(50), JSON_VALUE(ProductMetadata, '$.color'));

CREATE INDEX IX_Products_MetadataColor
ON dbo.Products(MetadataColor);

CREATE PARTITION FUNCTION PF_DP800_OrderDate(date)
AS RANGE RIGHT FOR VALUES ('2026-01-01', '2026-04-01', '2026-07-01', '2026-10-01');

CREATE PARTITION SCHEME PS_DP800_OrderDate
AS PARTITION PF_DP800_OrderDate ALL TO ([PRIMARY]);

CREATE TABLE dbo.PartitionedOrders
(
    OrderID bigint IDENTITY(1,1) NOT NULL,
    OrderDate date NOT NULL,
    CustomerName nvarchar(100) NOT NULL,
    TotalAmount decimal(12,2) NOT NULL,
    CONSTRAINT PK_PartitionedOrders PRIMARY KEY (OrderID, OrderDate)
) ON PS_DP800_OrderDate(OrderDate);

INSERT dbo.PartitionedOrders (OrderDate, CustomerName, TotalAmount) VALUES
    ('2026-01-15', N'Avery Chen', 1543.90),
    ('2026-05-12', N'Morgan Lee', 125.00),
    ('2026-08-03', N'Jordan Patel', 39.00);

CREATE TABLE dbo.ProductNode
(
    ProductID int NOT NULL,
    ProductName nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE dbo.ProductRelatedTo
(
    RelationshipType nvarchar(30) NOT NULL
) AS EDGE;

INSERT dbo.ProductNode (ProductID, ProductName)
SELECT ProductID, ProductName FROM dbo.Products;

INSERT dbo.ProductRelatedTo ($from_id, $to_id, RelationshipType)
SELECT sourceNode.$node_id, targetNode.$node_id, N'complements'
FROM dbo.ProductNode AS sourceNode
CROSS JOIN dbo.ProductNode AS targetNode
WHERE sourceNode.ProductID = 1 AND targetNode.ProductID IN (2, 3);
GO
