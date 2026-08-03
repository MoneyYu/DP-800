SET NOCOUNT ON;
GO

DROP VIEW IF EXISTS dbo.ProductCatalogView;
DROP TABLE IF EXISTS dbo.ApiProducts;
DROP TABLE IF EXISTS dbo.ApiCategories;

CREATE TABLE dbo.ApiCategories
(
    CategoryID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ApiCategories PRIMARY KEY,
    CategoryName nvarchar(50) NOT NULL
);

CREATE TABLE dbo.ApiProducts
(
    ProductID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ApiProducts PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    CategoryID int NOT NULL CONSTRAINT FK_ApiProducts_ApiCategories REFERENCES dbo.ApiCategories(CategoryID),
    UnitPrice decimal(10,2) NOT NULL,
    UnitsInStock int NOT NULL,
    Discontinued bit NOT NULL CONSTRAINT DF_ApiProducts_Discontinued DEFAULT 0
);

INSERT dbo.ApiCategories (CategoryName) VALUES (N'Bikes'), (N'Components'), (N'Accessories');
INSERT dbo.ApiProducts (ProductName, CategoryID, UnitPrice, UnitsInStock) VALUES
    (N'Trailblazer 29 Bike', 1, 1499.00, 8),
    (N'Puncture Guard Tire', 2, 62.50, 40),
    (N'Night Beacon Light', 3, 44.90, 0);
GO

CREATE OR ALTER VIEW dbo.ProductCatalogView
AS
SELECT
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    p.UnitPrice,
    p.UnitsInStock,
    CASE WHEN p.UnitsInStock = 0 THEN N'Out of stock'
         WHEN p.UnitsInStock < 10 THEN N'Low stock'
         ELSE N'Available' END AS StockStatus
FROM dbo.ApiProducts AS p
INNER JOIN dbo.ApiCategories AS c ON c.CategoryID = p.CategoryID
WHERE p.Discontinued = 0;
GO
