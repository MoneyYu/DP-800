SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.ProductPrice', N'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.ProductPrice SET (SYSTEM_VERSIONING = OFF);
    DROP TABLE dbo.ProductPrice;
END;
DROP TABLE IF EXISTS dbo.ProductPriceHistory;

IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID(N'dbo.ProductReviews', N'U') IS NOT NULL DROP TABLE dbo.ProductReviews;
IF OBJECT_ID(N'dbo.Products', N'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID(N'dbo.Customers', N'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

CREATE TABLE dbo.Customers
(
    CustomerID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    Email nvarchar(200) NOT NULL,
    SalesRegion nvarchar(20) NOT NULL
);

CREATE TABLE dbo.Products
(
    ProductID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    Category nvarchar(50) NOT NULL,
    UnitPrice decimal(10,2) NOT NULL CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice > 0),
    ProductMetadata nvarchar(max) NULL CONSTRAINT CK_Products_Metadata CHECK (ProductMetadata IS NULL OR ISJSON(ProductMetadata) = 1)
);

CREATE TABLE dbo.Orders
(
    OrderID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerID int NOT NULL CONSTRAINT FK_Orders_Customers REFERENCES dbo.Customers(CustomerID),
    OrderDate datetime2(0) NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT SYSUTCDATETIME(),
    OrderStatus nvarchar(20) NOT NULL
);

CREATE TABLE dbo.OrderItems
(
    OrderItemID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderItems PRIMARY KEY,
    OrderID int NOT NULL CONSTRAINT FK_OrderItems_Orders REFERENCES dbo.Orders(OrderID),
    ProductID int NOT NULL CONSTRAINT FK_OrderItems_Products REFERENCES dbo.Products(ProductID),
    Quantity int NOT NULL CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    UnitPrice decimal(10,2) NOT NULL
);

CREATE TABLE dbo.ProductReviews
(
    ReviewID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProductReviews PRIMARY KEY,
    ProductID int NOT NULL CONSTRAINT FK_ProductReviews_Products REFERENCES dbo.Products(ProductID),
    ReviewTitle nvarchar(200) NOT NULL,
    ReviewText nvarchar(max) NOT NULL,
    Rating tinyint NOT NULL CONSTRAINT CK_ProductReviews_Rating CHECK (Rating BETWEEN 1 AND 5)
);
GO

INSERT dbo.Customers (CustomerName, Email, SalesRegion) VALUES
    (N'Avery Chen', N'avery.chen@example.invalid', N'West'),
    (N'Morgan Lee', N'morgan.lee@example.invalid', N'East'),
    (N'Jordan Patel', N'jordan.patel@example.invalid', N'Central');

INSERT dbo.Products (ProductName, Category, UnitPrice, ProductMetadata) VALUES
    (N'Trailblazer 29 Bike', N'Bikes', 1499.00, N'{"terrain":"rocky trails","frame":"aluminum"}'),
    (N'Puncture Guard Tire', N'Components', 62.50, N'{"feature":"puncture resistant","size":"29 inch"}'),
    (N'Night Beacon Light', N'Accessories', 44.90, N'{"lumens":800,"weather":"rain"}'),
    (N'Winter Grip Gloves', N'Clothing', 39.00, N'{"season":"winter","insulated":true}');

INSERT dbo.Orders (CustomerID, OrderDate, OrderStatus) VALUES
    (1, DATEADD(day, -20, SYSUTCDATETIME()), N'Delivered'),
    (2, DATEADD(day, -5, SYSUTCDATETIME()), N'Shipped'),
    (3, DATEADD(day, -1, SYSUTCDATETIME()), N'Processing');

INSERT dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice) VALUES
    (1, 1, 1, 1499.00), (1, 3, 1, 44.90), (2, 2, 2, 62.50), (3, 4, 1, 39.00);

INSERT dbo.ProductReviews (ProductID, ReviewTitle, ReviewText, Rating) VALUES
    (1, N'Confident on technical trails', N'Stable handling over rocky climbs and precise control on steep descents.', 5),
    (2, N'No flats on gravel', N'The tire resisted punctures during long rides on rough gravel roads.', 5),
    (3, N'Visible in heavy rain', N'Bright beam and reliable weather sealing for dark wet commutes.', 4),
    (4, N'Warm without bulk', N'Kept my hands warm below freezing while preserving brake control.', 5),
    (2, N'Durable commuter tire', N'Good tread life and dependable protection from road debris.', 4);
GO
