/*
    M08 common setup — REST/GraphQL API surface for AdventureGearAI.

    Instead of creating duplicate ApiProducts/ApiCategories tables, this script
    projects the canonical AdventureGearAI domain data through read-only views in
    the api schema. Data API Builder (common/dab-config.json) exposes these views
    over REST and GraphQL. The api schema is created by the core bootstrap; this
    script is idempotent and safe to re-run.
    M08 共用設定：AdventureGearAI 的 REST/GraphQL API 介面。
    此指令碼不會建立重複的 ApiProducts/ApiCategories 資料表，而是在 api 結構描述中的唯讀檢視表投影標準 AdventureGearAI 網域資料。Data API Builder（common/dab-config.json）會透過 REST 和 GraphQL 公開這些檢視表。api 結構描述由核心 bootstrap 建立；此指令碼具冪等性，且可安全地重新執行。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

/* Remove any legacy duplicate API tables/views from earlier per-module demos.
   移除先前每一模組示範遺留的任何重複 API 資料表/檢視表。
   */
DROP VIEW IF EXISTS dbo.ProductCatalogView;
DROP TABLE IF EXISTS dbo.ApiProducts;
DROP TABLE IF EXISTS dbo.ApiCategories;
GO

CREATE OR ALTER VIEW api.Categories
AS
SELECT
    c.CategoryID,
    c.CategoryName,
    c.Description,
    c.IsActive
FROM catalog.Categories AS c;
GO

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
LEFT JOIN catalog.Inventory AS i ON i.ProductID = p.ProductID;
GO

CREATE OR ALTER VIEW api.ProductCatalog
AS
SELECT
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    p.UnitPrice,
    COALESCE(i.QuantityOnHand, 0) AS UnitsInStock,
    CASE
        WHEN COALESCE(i.QuantityOnHand, 0) = 0 THEN N'Out of stock'
        WHEN i.QuantityOnHand < i.ReorderThreshold THEN N'Low stock'
        ELSE N'Available'
    END AS StockStatus
FROM catalog.Products AS p
INNER JOIN catalog.Categories AS c ON c.CategoryID = p.CategoryID
LEFT JOIN catalog.Inventory AS i ON i.ProductID = p.ProductID
WHERE p.IsActive = 1;
GO

CREATE OR ALTER VIEW api.InventoryAvailability
AS
SELECT
    i.ProductID,
    p.ProductName,
    i.QuantityOnHand,
    i.ReorderThreshold,
    i.WarehouseLocation,
    CASE
        WHEN i.QuantityOnHand = 0 THEN N'Out of stock'
        WHEN i.QuantityOnHand < i.ReorderThreshold THEN N'Reorder'
        ELSE N'In stock'
    END AS AvailabilityStatus
FROM catalog.Inventory AS i
INNER JOIN catalog.Products AS p ON p.ProductID = i.ProductID;
GO

PRINT N'M08 api.* views over the AdventureGearAI catalog are ready.';
GO
