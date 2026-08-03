/*
    01-initialize-adventuregear-demo.sql

    Initializes the unified AdventureGearAI demo database:
      * Domain schemas: catalog, sales, customer, security, ops, api, search, ai.
      * Operational tracking: ops.DemoEnvironment marker and ops.DemoModuleState.
      * Canonical realistic (fictional) ecommerce core used by every module:
        catalog.Categories / catalog.Products / catalog.Inventory,
        customer.Customers / customer.ProductReviews,
        sales.Orders / sales.OrderItems.

    The script is idempotent: every object and seed block is guarded so the
    bootstrap can be re-run safely. Module-specific (M01..M11) advanced objects
    are intentionally NOT created here; they are provisioned by later module
    runners against this same AdventureGearAI database.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE [AdventureGearAI];
GO

/* ---------------------------------------------------------------------------
   Domain schemas (CREATE SCHEMA must be the first statement in its batch, so
   each guarded creation is executed via EXEC for idempotency).
--------------------------------------------------------------------------- */
IF SCHEMA_ID(N'catalog') IS NULL EXEC (N'CREATE SCHEMA catalog;');
GO
IF SCHEMA_ID(N'sales') IS NULL EXEC (N'CREATE SCHEMA sales;');
GO
IF SCHEMA_ID(N'customer') IS NULL EXEC (N'CREATE SCHEMA customer;');
GO
IF SCHEMA_ID(N'security') IS NULL EXEC (N'CREATE SCHEMA security;');
GO
IF SCHEMA_ID(N'ops') IS NULL EXEC (N'CREATE SCHEMA ops;');
GO
IF SCHEMA_ID(N'api') IS NULL EXEC (N'CREATE SCHEMA api;');
GO
IF SCHEMA_ID(N'search') IS NULL EXEC (N'CREATE SCHEMA search;');
GO
IF SCHEMA_ID(N'ai') IS NULL EXEC (N'CREATE SCHEMA ai;');
GO

/* ---------------------------------------------------------------------------
   Operational tracking tables.
--------------------------------------------------------------------------- */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
BEGIN
    CREATE TABLE ops.DemoEnvironment
    (
        DemoEnvironmentID tinyint NOT NULL
            CONSTRAINT PK_DemoEnvironment PRIMARY KEY
            CONSTRAINT CK_DemoEnvironment_Singleton CHECK (DemoEnvironmentID = 1),
        DatabaseName sysname NOT NULL
            CONSTRAINT CK_DemoEnvironment_DatabaseName CHECK (DatabaseName = N'AdventureGearAI'),
        DemoName nvarchar(100) NOT NULL,
        SchemaVersion nvarchar(20) NOT NULL,
        InitializedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_DemoEnvironment_InitializedAtUtc DEFAULT SYSUTCDATETIME(),
        UpdatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_DemoEnvironment_UpdatedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'ops.DemoModuleState', N'U') IS NULL
BEGIN
    CREATE TABLE ops.DemoModuleState
    (
        ModuleNumber tinyint NOT NULL
            CONSTRAINT PK_DemoModuleState PRIMARY KEY
            CONSTRAINT CK_DemoModuleState_ModuleNumber CHECK (ModuleNumber BETWEEN 1 AND 11),
        ModuleName AS (CONCAT(N'M', RIGHT(CONCAT(N'0', ModuleNumber), 2))) PERSISTED,
        Status nvarchar(20) NOT NULL
            CONSTRAINT DF_DemoModuleState_Status DEFAULT N'NotStarted'
            CONSTRAINT CK_DemoModuleState_Status
                CHECK (Status IN (N'NotStarted', N'Running', N'Completed', N'Failed', N'Skipped')),
        StartedAtUtc datetime2(3) NULL,
        CompletedAtUtc datetime2(3) NULL,
        LastError nvarchar(max) NULL,
        ErrorNumber int NULL,
        ErrorLine int NULL,
        UpdatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_DemoModuleState_UpdatedAtUtc DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_DemoModuleState_Timestamps
            CHECK (CompletedAtUtc IS NULL OR StartedAtUtc IS NULL OR CompletedAtUtc >= StartedAtUtc)
    );
END;
GO

/* ---------------------------------------------------------------------------
   Canonical ecommerce core.
--------------------------------------------------------------------------- */
IF OBJECT_ID(N'catalog.Categories', N'U') IS NULL
BEGIN
    CREATE TABLE catalog.Categories
    (
        CategoryID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Categories PRIMARY KEY,
        CategoryName nvarchar(80) NOT NULL
            CONSTRAINT UQ_Categories_Name UNIQUE,
        Description nvarchar(400) NULL,
        IsActive bit NOT NULL
            CONSTRAINT DF_Categories_IsActive DEFAULT 1
    );
END;
GO

IF OBJECT_ID(N'catalog.Products', N'U') IS NULL
BEGIN
    CREATE TABLE catalog.Products
    (
        ProductID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Products PRIMARY KEY,
        CategoryID int NOT NULL
            CONSTRAINT FK_Products_Categories REFERENCES catalog.Categories(CategoryID),
        ProductName nvarchar(120) NOT NULL,
        Sku nvarchar(40) NOT NULL
            CONSTRAINT UQ_Products_Sku UNIQUE,
        UnitPrice decimal(10,2) NOT NULL
            CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice > 0),
        ProductMetadata nvarchar(max) NULL
            CONSTRAINT CK_Products_Metadata CHECK (ProductMetadata IS NULL OR ISJSON(ProductMetadata) = 1),
        IsActive bit NOT NULL
            CONSTRAINT DF_Products_IsActive DEFAULT 1,
        CreatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_Products_CreatedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'catalog.Inventory', N'U') IS NULL
BEGIN
    CREATE TABLE catalog.Inventory
    (
        ProductID int NOT NULL
            CONSTRAINT PK_Inventory PRIMARY KEY
            CONSTRAINT FK_Inventory_Products REFERENCES catalog.Products(ProductID),
        QuantityOnHand int NOT NULL
            CONSTRAINT CK_Inventory_QuantityOnHand CHECK (QuantityOnHand >= 0),
        ReorderThreshold int NOT NULL
            CONSTRAINT DF_Inventory_ReorderThreshold DEFAULT 10
            CONSTRAINT CK_Inventory_ReorderThreshold CHECK (ReorderThreshold >= 0),
        WarehouseLocation nvarchar(60) NULL,
        UpdatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_Inventory_UpdatedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'customer.Customers', N'U') IS NULL
BEGIN
    CREATE TABLE customer.Customers
    (
        CustomerID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Customers PRIMARY KEY,
        CustomerName nvarchar(120) NOT NULL,
        Email nvarchar(200) NOT NULL
            CONSTRAINT UQ_Customers_Email UNIQUE,
        SalesRegion nvarchar(20) NOT NULL
            CONSTRAINT CK_Customers_SalesRegion
                CHECK (SalesRegion IN (N'West', N'East', N'Central', N'North', N'South')),
        Preferences nvarchar(max) NULL
            CONSTRAINT CK_Customers_Preferences CHECK (Preferences IS NULL OR ISJSON(Preferences) = 1),
        CreatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_Customers_CreatedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'customer.ProductReviews', N'U') IS NULL
BEGIN
    CREATE TABLE customer.ProductReviews
    (
        ReviewID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_ProductReviews PRIMARY KEY,
        ProductID int NOT NULL
            CONSTRAINT FK_ProductReviews_Products REFERENCES catalog.Products(ProductID),
        CustomerID int NULL
            CONSTRAINT FK_ProductReviews_Customers REFERENCES customer.Customers(CustomerID),
        ReviewTitle nvarchar(200) NOT NULL,
        ReviewText nvarchar(max) NOT NULL,
        Rating tinyint NOT NULL
            CONSTRAINT CK_ProductReviews_Rating CHECK (Rating BETWEEN 1 AND 5),
        CreatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_ProductReviews_CreatedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'sales.Orders', N'U') IS NULL
BEGIN
    CREATE TABLE sales.Orders
    (
        OrderID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Orders PRIMARY KEY,
        CustomerID int NOT NULL
            CONSTRAINT FK_Orders_Customers REFERENCES customer.Customers(CustomerID),
        OrderDate datetime2(0) NOT NULL
            CONSTRAINT DF_Orders_OrderDate DEFAULT SYSUTCDATETIME(),
        OrderStatus nvarchar(20) NOT NULL
            CONSTRAINT CK_Orders_OrderStatus
                CHECK (OrderStatus IN (N'Pending', N'Processing', N'Shipped', N'Delivered', N'Cancelled')),
        ShippingMetadata nvarchar(max) NULL
            CONSTRAINT CK_Orders_ShippingMetadata CHECK (ShippingMetadata IS NULL OR ISJSON(ShippingMetadata) = 1)
    );
END;
GO

IF OBJECT_ID(N'sales.OrderItems', N'U') IS NULL
BEGIN
    CREATE TABLE sales.OrderItems
    (
        OrderItemID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_OrderItems PRIMARY KEY,
        OrderID int NOT NULL
            CONSTRAINT FK_OrderItems_Orders REFERENCES sales.Orders(OrderID),
        ProductID int NOT NULL
            CONSTRAINT FK_OrderItems_Products REFERENCES catalog.Products(ProductID),
        Quantity int NOT NULL
            CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
        UnitPrice decimal(10,2) NOT NULL
            CONSTRAINT CK_OrderItems_UnitPrice CHECK (UnitPrice >= 0),
        CONSTRAINT UQ_OrderItems_Order_Product UNIQUE (OrderID, ProductID)
    );
END;
GO

/* ---------------------------------------------------------------------------
   Operational seed: environment marker and module state rows.
--------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment)
BEGIN
    INSERT ops.DemoEnvironment (DemoEnvironmentID, DatabaseName, DemoName, SchemaVersion)
    VALUES (1, N'AdventureGearAI', N'AdventureGearAI unified demo', N'1.0.0');
END;
GO

INSERT ops.DemoModuleState (ModuleNumber)
SELECT n.ModuleNumber
FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11)) AS n(ModuleNumber)
WHERE NOT EXISTS (SELECT 1 FROM ops.DemoModuleState s WHERE s.ModuleNumber = n.ModuleNumber);
GO

/* ---------------------------------------------------------------------------
   Ecommerce core seed (guarded; deterministic identity values so foreign keys
   in later seed blocks and module demos remain stable across re-runs).
--------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM catalog.Categories)
BEGIN
    SET IDENTITY_INSERT catalog.Categories ON;
    INSERT catalog.Categories (CategoryID, CategoryName, Description) VALUES
        (1, N'Bikes', N'Mountain, gravel, and trail bikes'),
        (2, N'Components', N'Drivetrain, tires, and replacement parts'),
        (3, N'Accessories', N'Lights, packs, and ride add-ons'),
        (4, N'Clothing', N'Technical apparel for all seasons'),
        (5, N'Navigation', N'GPS units and route computers');
    SET IDENTITY_INSERT catalog.Categories OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM catalog.Products)
BEGIN
    SET IDENTITY_INSERT catalog.Products ON;
    INSERT catalog.Products (ProductID, CategoryID, ProductName, Sku, UnitPrice, ProductMetadata) VALUES
        (1, 1, N'Trailblazer 29 Bike', N'BIKE-TB29', 1499.00, N'{"terrain":"rocky trails","frame":"aluminum","wheelSize":29}'),
        (2, 1, N'Summit Carbon Bike', N'BIKE-SC01', 2899.00, N'{"terrain":"alpine","frame":"carbon","wheelSize":29}'),
        (3, 1, N'Gravel Rambler Bike', N'BIKE-GR07', 1899.00, N'{"terrain":"gravel","frame":"steel","wheelSize":28}'),
        (4, 2, N'Puncture Guard Tire', N'COMP-PGT2', 62.50, N'{"feature":"puncture resistant","size":"29 inch"}'),
        (5, 2, N'Trail Drive Chain', N'COMP-TDC9', 48.75, N'{"speeds":12,"material":"nickel"}'),
        (6, 2, N'Hydraulic Disc Brake', N'COMP-HDB4', 129.00, N'{"type":"hydraulic","rotor":"180mm"}'),
        (7, 3, N'Night Beacon Light', N'ACC-NBL8', 44.90, N'{"lumens":800,"weather":"rain"}'),
        (8, 3, N'Backcountry Hydration Pack', N'ACC-BHP3', 89.00, N'{"capacity":"2L","pockets":5}'),
        (9, 4, N'Winter Grip Gloves', N'CLO-WGG1', 39.00, N'{"season":"winter","insulated":true}'),
        (10, 4, N'All-Weather Trail Jacket', N'CLO-ATJ6', 159.00, N'{"waterproof":true,"packable":true}'),
        (11, 5, N'Summit GPS Computer', N'NAV-SGC5', 279.00, N'{"battery":"20h","maps":"topographic"}'),
        (12, 5, N'Compact Route Beacon', N'NAV-CRB2', 119.00, N'{"battery":"36h","connectivity":"bluetooth"}');
    SET IDENTITY_INSERT catalog.Products OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM catalog.Inventory)
BEGIN
    INSERT catalog.Inventory (ProductID, QuantityOnHand, ReorderThreshold, WarehouseLocation) VALUES
        (1, 24, 5, N'WH-West'),
        (2, 8, 3, N'WH-West'),
        (3, 15, 5, N'WH-Central'),
        (4, 240, 40, N'WH-East'),
        (5, 180, 30, N'WH-East'),
        (6, 60, 12, N'WH-Central'),
        (7, 320, 50, N'WH-East'),
        (8, 95, 20, N'WH-West'),
        (9, 210, 40, N'WH-Central'),
        (10, 70, 15, N'WH-West'),
        (11, 45, 10, N'WH-East'),
        (12, 130, 25, N'WH-Central');
END;
GO

IF NOT EXISTS (SELECT 1 FROM customer.Customers)
BEGIN
    SET IDENTITY_INSERT customer.Customers ON;
    INSERT customer.Customers (CustomerID, CustomerName, Email, SalesRegion, Preferences) VALUES
        (1, N'Avery Chen', N'avery.chen@example.invalid', N'West', N'{"newsletter":true,"preferredCategory":"Bikes"}'),
        (2, N'Morgan Lee', N'morgan.lee@example.invalid', N'East', N'{"newsletter":false,"preferredCategory":"Components"}'),
        (3, N'Jordan Patel', N'jordan.patel@example.invalid', N'Central', N'{"newsletter":true,"preferredCategory":"Navigation"}'),
        (4, N'Riley Nguyen', N'riley.nguyen@example.invalid', N'North', N'{"newsletter":true,"preferredCategory":"Clothing"}'),
        (5, N'Casey Flores', N'casey.flores@example.invalid', N'South', N'{"newsletter":false,"preferredCategory":"Accessories"}'),
        (6, N'Devon Brooks', N'devon.brooks@example.invalid', N'West', N'{"newsletter":true,"preferredCategory":"Bikes"}');
    SET IDENTITY_INSERT customer.Customers OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sales.Orders)
BEGIN
    SET IDENTITY_INSERT sales.Orders ON;
    INSERT sales.Orders (OrderID, CustomerID, OrderDate, OrderStatus, ShippingMetadata) VALUES
        (1, 1, DATEADD(day, -20, SYSUTCDATETIME()), N'Delivered', N'{"carrier":"TrailExpress","priority":"standard"}'),
        (2, 2, DATEADD(day, -12, SYSUTCDATETIME()), N'Shipped', N'{"carrier":"TrailExpress","priority":"express"}'),
        (3, 3, DATEADD(day, -6, SYSUTCDATETIME()), N'Processing', N'{"carrier":"RidgeLogistics","priority":"standard"}'),
        (4, 4, DATEADD(day, -3, SYSUTCDATETIME()), N'Pending', N'{"carrier":"RidgeLogistics","priority":"standard"}'),
        (5, 5, DATEADD(day, -1, SYSUTCDATETIME()), N'Processing', N'{"carrier":"TrailExpress","priority":"express"}'),
        (6, 6, DATEADD(day, -30, SYSUTCDATETIME()), N'Delivered', N'{"carrier":"RidgeLogistics","priority":"standard"}');
    SET IDENTITY_INSERT sales.Orders OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sales.OrderItems)
BEGIN
    INSERT sales.OrderItems (OrderID, ProductID, Quantity, UnitPrice) VALUES
        (1, 1, 1, 1499.00),
        (1, 7, 1, 44.90),
        (2, 4, 2, 62.50),
        (2, 5, 1, 48.75),
        (3, 11, 1, 279.00),
        (3, 8, 1, 89.00),
        (4, 10, 1, 159.00),
        (4, 9, 2, 39.00),
        (5, 6, 1, 129.00),
        (5, 12, 1, 119.00),
        (6, 2, 1, 2899.00),
        (6, 3, 1, 1899.00),
        (6, 7, 2, 44.90);
END;
GO

IF NOT EXISTS (SELECT 1 FROM customer.ProductReviews)
BEGIN
    INSERT customer.ProductReviews (ProductID, CustomerID, ReviewTitle, ReviewText, Rating) VALUES
        (1, 1, N'Confident on technical trails', N'Stable handling over rocky climbs and precise control on steep descents.', 5),
        (1, 6, N'Great all-round trail bike', N'Comfortable geometry and dependable braking on long rides.', 4),
        (2, 6, N'Feathery and fast', N'The carbon frame climbs effortlessly and stays planted at speed.', 5),
        (3, 3, N'Perfect gravel companion', N'Soaks up chatter on rough roads while staying efficient.', 4),
        (4, 2, N'No flats on gravel', N'The tire resisted punctures during long rides on rough gravel roads.', 5),
        (4, 5, N'Durable commuter tire', N'Good tread life and dependable protection from road debris.', 4),
        (5, 2, N'Smooth and quiet', N'Shifts cleanly and runs quietly even under load.', 4),
        (6, 5, N'Strong stopping power', N'Consistent modulation in wet and dry conditions.', 5),
        (7, 1, N'Visible in heavy rain', N'Bright beam and reliable weather sealing for dark wet commutes.', 4),
        (8, 3, N'Carries everything I need', N'Comfortable straps and plenty of organized storage.', 4),
        (9, 4, N'Warm without bulk', N'Kept my hands warm below freezing while preserving brake control.', 5),
        (10, 4, N'Reliable in downpours', N'Fully waterproof yet breathable on climbs.', 5),
        (11, 3, N'Accurate navigation', N'Clear topographic maps and long battery life on all-day rides.', 5),
        (12, 3, N'Compact and dependable', N'Simple routing with excellent battery endurance.', 4);
END;
GO

/* Refresh the environment marker timestamp so re-runs record the latest init. */
UPDATE ops.DemoEnvironment
SET UpdatedAtUtc = SYSUTCDATETIME()
WHERE DemoEnvironmentID = 1;
GO

PRINT N'AdventureGearAI demo initialization complete.';
GO
