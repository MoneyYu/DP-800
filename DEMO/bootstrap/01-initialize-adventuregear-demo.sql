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
    01-initialize-adventuregear-demo.sql
    初始化統一 AdventureGearAI 示範資料庫：網域結構描述 catalog、sales、customer、security、ops、api、search、ai；作業追蹤 ops.DemoEnvironment 標記與 ops.DemoModuleState；以及每個模組使用的標準逼真（虛構）電子商務核心：catalog.Categories / catalog.Products / catalog.Inventory、customer.Customers / customer.ProductReviews、sales.Orders / sales.OrderItems。
    此指令碼具冪等性：每個物件與植入區塊都受防護，因此可安全重新執行 bootstrap。模組專屬（M01..M11）的進階物件刻意不在此處建立；後續模組執行器會針對同一個 AdventureGearAI 資料庫佈建它們。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE [AdventureGearAI];
GO

DECLARE @compatibilityLevel int = (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID());
IF @compatibilityLevel < 170
    THROW 51000, N'AdventureGearAI requires database compatibility level 170 or higher to use the native json data type.', 1;
GO

/* ---------------------------------------------------------------------------
   Domain schemas (CREATE SCHEMA must be the first statement in its batch, so
   each guarded creation is executed via EXEC for idempotency).
---------------------------------------------------------------------------
網域結構描述（CREATE SCHEMA 必須是其批次的第一個陳述式，因此每個受防護的建立作業都透過 EXEC 執行以維持冪等性）。
*/
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
---------------------------------------------------------------------------
作業追蹤資料表。
*/
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
        SchemaVersion nvarchar(40) NOT NULL,
        InitializedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_DemoEnvironment_InitializedAtUtc DEFAULT SYSUTCDATETIME(),
        UpdatedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_DemoEnvironment_UpdatedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;

IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'ops.DemoEnvironment')
      AND name = N'SchemaVersion'
      AND max_length < 80
)
    ALTER TABLE ops.DemoEnvironment ALTER COLUMN SchemaVersion nvarchar(40) NOT NULL;
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

/* Bootstrap owns only the IDs recorded here.  The registry version documents
   the deterministic seed contract and prevents reruns from enriching user data. */
IF OBJECT_ID(N'ops.BootstrapSeedRegistry', N'U') IS NULL
BEGIN
    CREATE TABLE ops.BootstrapSeedRegistry
    (
        SeedEntity nvarchar(20) NOT NULL,
        SeedID int NOT NULL,
        SeedVersion nvarchar(40) NOT NULL,
        RecordedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_BootstrapSeedRegistry_RecordedAtUtc DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_BootstrapSeedRegistry PRIMARY KEY (SeedEntity, SeedID)
    );
END;

/* OUTPUT INTO cannot target tables with enabled check constraints. Remove the
   short-lived initial constraint names from interrupted pre-release runs. */
IF OBJECT_ID(N'ops.CK_BootstrapSeedRegistry_SeedEntity', N'C') IS NOT NULL
    ALTER TABLE ops.BootstrapSeedRegistry DROP CONSTRAINT CK_BootstrapSeedRegistry_SeedEntity;
IF OBJECT_ID(N'ops.CK_BootstrapSeedRegistry_SeedID', N'C') IS NOT NULL
    ALTER TABLE ops.BootstrapSeedRegistry DROP CONSTRAINT CK_BootstrapSeedRegistry_SeedID;
GO

/* ---------------------------------------------------------------------------
   Canonical ecommerce core.
---------------------------------------------------------------------------
標準電子商務核心。
*/
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
        ProductMetadata json NULL,
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
        Preferences json NULL,
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
        ShippingMetadata json NULL
    );
END;
GO

/* Upgrade the three former nvarchar JSON documents in-place.  The nullability
   is read from the existing column so upgrades do not weaken that contract. */
IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'catalog.Products')
      AND name = N'ProductMetadata'
      AND system_type_id <> TYPE_ID(N'json')
)
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'catalog.Products')
          AND name = N'CK_Products_Metadata'
    )
        ALTER TABLE catalog.Products DROP CONSTRAINT CK_Products_Metadata;

    DECLARE @productMetadataNullability nvarchar(8) =
        CASE WHEN COLUMNPROPERTY(OBJECT_ID(N'catalog.Products'), N'ProductMetadata', 'AllowsNull') = 1
             THEN N'NULL' ELSE N'NOT NULL' END;
    EXEC (N'ALTER TABLE catalog.Products ALTER COLUMN ProductMetadata json ' + @productMetadataNullability + N';');
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'customer.Customers')
      AND name = N'Preferences'
      AND system_type_id <> TYPE_ID(N'json')
)
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'customer.Customers')
          AND name = N'CK_Customers_Preferences'
    )
        ALTER TABLE customer.Customers DROP CONSTRAINT CK_Customers_Preferences;

    DECLARE @preferencesNullability nvarchar(8) =
        CASE WHEN COLUMNPROPERTY(OBJECT_ID(N'customer.Customers'), N'Preferences', 'AllowsNull') = 1
             THEN N'NULL' ELSE N'NOT NULL' END;
    EXEC (N'ALTER TABLE customer.Customers ALTER COLUMN Preferences json ' + @preferencesNullability + N';');
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'sales.Orders')
      AND name = N'ShippingMetadata'
      AND system_type_id <> TYPE_ID(N'json')
)
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'sales.Orders')
          AND name = N'CK_Orders_ShippingMetadata'
    )
        ALTER TABLE sales.Orders DROP CONSTRAINT CK_Orders_ShippingMetadata;

    DECLARE @shippingMetadataNullability nvarchar(8) =
        CASE WHEN COLUMNPROPERTY(OBJECT_ID(N'sales.Orders'), N'ShippingMetadata', 'AllowsNull') = 1
             THEN N'NULL' ELSE N'NOT NULL' END;
    EXEC (N'ALTER TABLE sales.Orders ALTER COLUMN ShippingMetadata json ' + @shippingMetadataNullability + N';');
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
---------------------------------------------------------------------------
作業植入：環境標記和模組狀態資料列。
*/
IF NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment)
BEGIN
    INSERT ops.DemoEnvironment (DemoEnvironmentID, DatabaseName, DemoName, SchemaVersion)
    VALUES (1, N'AdventureGearAI', N'AdventureGearAI unified demo', N'2.1.0-json170-seedownership');
END;
GO

UPDATE ops.DemoEnvironment
SET SchemaVersion = N'2.1.0-json170-seedownership',
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE DemoEnvironmentID = 1
  AND SchemaVersion <> N'2.1.0-json170-seedownership';
GO

INSERT ops.DemoModuleState (ModuleNumber)
SELECT n.ModuleNumber
FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11)) AS n(ModuleNumber)
WHERE NOT EXISTS (SELECT 1 FROM ops.DemoModuleState s WHERE s.ModuleNumber = n.ModuleNumber);
GO

/* ---------------------------------------------------------------------------
   Ecommerce core seed (guarded; deterministic identity values so foreign keys
   in later seed blocks and module demos remain stable across re-runs).
---------------------------------------------------------------------------
電子商務核心植入（受防護；使用決定性的身分識別值，因此後續植入區塊和模組示範中的外部索引鍵可在重新執行時保持穩定）。
*/
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
    INSERT catalog.Products (ProductID, CategoryID, ProductName, Sku, UnitPrice, ProductMetadata)
    OUTPUT N'Product', INSERTED.ProductID, N'2.1.0-seed-ownership'
        INTO ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
    VALUES
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
    INSERT customer.Customers (CustomerID, CustomerName, Email, SalesRegion, Preferences)
    OUTPUT N'Customer', INSERTED.CustomerID, N'2.1.0-seed-ownership'
        INTO ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
    VALUES
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
    INSERT sales.Orders (OrderID, CustomerID, OrderDate, OrderStatus, ShippingMetadata)
    OUTPUT N'Order', INSERTED.OrderID, N'2.1.0-seed-ownership'
        INTO ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
    VALUES
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

/* Expand the canonical core deterministically.  Stable explicit identifiers
   preserve the original examples while the set-based ranges make every rerun
   converge on the same teaching dataset. */
SET IDENTITY_INSERT catalog.Categories ON;
INSERT catalog.Categories (CategoryID, CategoryName, Description)
SELECT v.CategoryID, v.CategoryName, v.Description
FROM (VALUES
    (6, N'Maintenance', N'Tools, cleaners, and workshop essentials'),
    (7, N'Safety', N'Helmets, protection, and visibility equipment'),
    (8, N'Training', N'Indoor training and performance accessories'),
    (9, N'Nutrition', N'Ride nutrition and hydration supplies'),
    (10, N'Travel', N'Bags, racks, and transport equipment')
) AS v(CategoryID, CategoryName, Description)
WHERE NOT EXISTS (SELECT 1 FROM catalog.Categories AS c WHERE c.CategoryID = v.CategoryID);
SET IDENTITY_INSERT catalog.Categories OFF;
GO

SET IDENTITY_INSERT catalog.Products ON;
;WITH e1(n) AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
numbers(n) AS
(
    SELECT TOP (138) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM e1 AS a CROSS JOIN e1 AS b CROSS JOIN e1 AS c
)
INSERT catalog.Products (ProductID, CategoryID, ProductName, Sku, UnitPrice, ProductMetadata)
OUTPUT N'Product', INSERTED.ProductID, N'2.1.0-seed-ownership'
    INTO ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
SELECT
    12 + n,
    ((11 + n) % 10) + 1,
    CONCAT(N'AdventureGear Series ', RIGHT(CONCAT(N'000', 12 + n), 3)),
    CONCAT(N'AG-', RIGHT(CONCAT(N'000', 12 + n), 3)),
    CONVERT(decimal(10, 2), 24.99 + (n * 7.25)),
    CONCAT(
        N'{"terrain":"mixed-surface","frame":"alloy","product":{"id":', 12 + n,
        N',"family":"AdventureGear Series","model":"AG-', RIGHT(CONCAT(N'000', 12 + n), 3),
        N'"},"specifications":{"weightKg":', CONVERT(nvarchar(20), CONVERT(decimal(5, 2), 6.5 + ((n % 20) * 0.15))),
        N',"dimensions":{"lengthCm":', 25 + (n % 60), N',"widthCm":', 8 + (n % 20),
        N'}},"features":["weather-ready","serviceable","demo-seed"],"tags":["category-',
        ((11 + n) % 10) + 1, N'","deterministic"],"warranty":{"years":2,"transferable":false}}'
    )
FROM numbers
WHERE NOT EXISTS (SELECT 1 FROM catalog.Products AS p WHERE p.ProductID = 12 + numbers.n);
SET IDENTITY_INSERT catalog.Products OFF;
GO

/* Upgrade pre-registry installations only when every deterministic value,
   including the rich JSON document, matches the published seed contract. */
INSERT ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
SELECT N'Product', p.ProductID, N'2.1.0-seed-ownership'
FROM catalog.Products AS p
WHERE NOT EXISTS
(
    SELECT 1
    FROM ops.BootstrapSeedRegistry AS ownership
    WHERE ownership.SeedEntity = N'Product'
      AND ownership.SeedID = p.ProductID
)
AND
(
    EXISTS
    (
        SELECT 1
        FROM (VALUES
            (1, 1, N'Trailblazer 29 Bike', N'BIKE-TB29', CONVERT(decimal(10,2), 1499.00)),
            (2, 1, N'Summit Carbon Bike', N'BIKE-SC01', CONVERT(decimal(10,2), 2899.00)),
            (3, 1, N'Gravel Rambler Bike', N'BIKE-GR07', CONVERT(decimal(10,2), 1899.00)),
            (4, 2, N'Puncture Guard Tire', N'COMP-PGT2', CONVERT(decimal(10,2), 62.50)),
            (5, 2, N'Trail Drive Chain', N'COMP-TDC9', CONVERT(decimal(10,2), 48.75)),
            (6, 2, N'Hydraulic Disc Brake', N'COMP-HDB4', CONVERT(decimal(10,2), 129.00)),
            (7, 3, N'Night Beacon Light', N'ACC-NBL8', CONVERT(decimal(10,2), 44.90)),
            (8, 3, N'Backcountry Hydration Pack', N'ACC-BHP3', CONVERT(decimal(10,2), 89.00)),
            (9, 4, N'Winter Grip Gloves', N'CLO-WGG1', CONVERT(decimal(10,2), 39.00)),
            (10, 4, N'All-Weather Trail Jacket', N'CLO-ATJ6', CONVERT(decimal(10,2), 159.00)),
            (11, 5, N'Summit GPS Computer', N'NAV-SGC5', CONVERT(decimal(10,2), 279.00)),
            (12, 5, N'Compact Route Beacon', N'NAV-CRB2', CONVERT(decimal(10,2), 119.00))
        ) AS v(ProductID, CategoryID, ProductName, Sku, UnitPrice)
        WHERE v.ProductID = p.ProductID
          AND v.CategoryID = p.CategoryID
          AND v.ProductName = p.ProductName
          AND v.Sku = p.Sku
          AND v.UnitPrice = p.UnitPrice
    )
    OR
    (
        p.ProductID BETWEEN 13 AND 150
        AND p.CategoryID = ((p.ProductID - 1) % 10) + 1
        AND p.ProductName = CONCAT(N'AdventureGear Series ', RIGHT(CONCAT(N'000', p.ProductID), 3))
        AND p.Sku = CONCAT(N'AG-', RIGHT(CONCAT(N'000', p.ProductID), 3))
        AND p.UnitPrice = CONVERT(decimal(10,2), 24.99 + ((p.ProductID - 12) * 7.25))
    )
)
AND CONVERT(nvarchar(max), p.ProductMetadata) = CONCAT(
    N'{"terrain":"',
    CASE p.ProductID WHEN 1 THEN N'rocky trails' WHEN 2 THEN N'alpine' WHEN 3 THEN N'gravel' ELSE N'mixed-surface' END,
    N'","frame":"',
    CASE p.ProductID WHEN 1 THEN N'aluminum' WHEN 2 THEN N'carbon' WHEN 3 THEN N'steel' ELSE N'alloy' END,
    N'","product":{"id":', p.ProductID, N',"name":"', REPLACE(p.ProductName, N'"', N'\"'),
    N'","sku":"', p.Sku, N'"},"specifications":{"wheelSize":',
    CASE WHEN p.ProductID IN (1, 2) THEN 29 WHEN p.ProductID = 3 THEN 28 ELSE 27 END,
    N',"price":', CONVERT(nvarchar(20), p.UnitPrice),
    N',"dimensions":{"lengthCm":', 80 + (p.ProductID % 30), N',"widthCm":', 20 + (p.ProductID % 10),
    N'}},"features":["weather-ready","serviceable","demo-seed"],"compatibility":{"terrainTags":["trail","all-weather"],"serviceIntervalsDays":[90,180]},"warranty":{"years":2,"transferable":false}}'
);
GO

UPDATE p
SET ProductMetadata = CONCAT(
    N'{"terrain":"',
    CASE p.ProductID WHEN 1 THEN N'rocky trails' WHEN 2 THEN N'alpine' WHEN 3 THEN N'gravel' ELSE N'mixed-surface' END,
    N'","frame":"',
    CASE p.ProductID WHEN 1 THEN N'aluminum' WHEN 2 THEN N'carbon' WHEN 3 THEN N'steel' ELSE N'alloy' END,
    N'","product":{"id":', p.ProductID, N',"name":"', REPLACE(p.ProductName, N'"', N'\"'),
    N'","sku":"', p.Sku, N'"},"specifications":{"wheelSize":',
    CASE WHEN p.ProductID IN (1, 2) THEN 29 WHEN p.ProductID = 3 THEN 28 ELSE 27 END,
    N',"price":', CONVERT(nvarchar(20), p.UnitPrice),
    N',"dimensions":{"lengthCm":', 80 + (p.ProductID % 30), N',"widthCm":', 20 + (p.ProductID % 10),
    N'}},"features":["weather-ready","serviceable","demo-seed"],"compatibility":{"terrainTags":["trail","all-weather"],"serviceIntervalsDays":[90,180]},"warranty":{"years":2,"transferable":false}}'
)
FROM catalog.Products AS p
JOIN ops.BootstrapSeedRegistry AS ownership
    ON ownership.SeedEntity = N'Product'
   AND ownership.SeedID = p.ProductID;
GO

;WITH e1(n) AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
numbers(n) AS
(
    SELECT TOP (138) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM e1 AS a CROSS JOIN e1 AS b CROSS JOIN e1 AS c
)
INSERT catalog.Inventory (ProductID, QuantityOnHand, ReorderThreshold, WarehouseLocation)
SELECT 12 + n, 30 + ((n * 17) % 220), 8 + (n % 30),
       CASE n % 3 WHEN 0 THEN N'WH-West' WHEN 1 THEN N'WH-East' ELSE N'WH-Central' END
FROM numbers
WHERE NOT EXISTS (SELECT 1 FROM catalog.Inventory AS i WHERE i.ProductID = 12 + numbers.n);
GO

SET IDENTITY_INSERT customer.Customers ON;
;WITH e1(n) AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
numbers(n) AS
(
    SELECT TOP (114) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM e1 AS a CROSS JOIN e1 AS b CROSS JOIN e1 AS c
)
INSERT customer.Customers (CustomerID, CustomerName, Email, SalesRegion, Preferences)
OUTPUT N'Customer', INSERTED.CustomerID, N'2.1.0-seed-ownership'
    INTO ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
SELECT
    6 + n,
    CONCAT(N'Demo Customer ', RIGHT(CONCAT(N'000', 6 + n), 3)),
    CONCAT(N'customer', RIGHT(CONCAT(N'000', 6 + n), 3), N'@example.invalid'),
    CASE (6 + n - 1) % 5
        WHEN 0 THEN N'West' WHEN 1 THEN N'East' WHEN 2 THEN N'Central' WHEN 3 THEN N'North' ELSE N'South'
    END,
    N'{"newsletter":true,"preferredCategory":"Bikes","profile":{"experience":"intermediate"},"notifications":{"channels":["email"]},"savedSearches":["trail"]}'
FROM numbers
WHERE NOT EXISTS (SELECT 1 FROM customer.Customers AS c WHERE c.CustomerID = 6 + numbers.n);
SET IDENTITY_INSERT customer.Customers OFF;
GO

INSERT ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
SELECT N'Customer', c.CustomerID, N'2.1.0-seed-ownership'
FROM customer.Customers AS c
WHERE NOT EXISTS
(
    SELECT 1
    FROM ops.BootstrapSeedRegistry AS ownership
    WHERE ownership.SeedEntity = N'Customer'
      AND ownership.SeedID = c.CustomerID
)
AND
(
    EXISTS
    (
        SELECT 1
        FROM (VALUES
            (1, N'Avery Chen', N'avery.chen@example.invalid', N'West'),
            (2, N'Morgan Lee', N'morgan.lee@example.invalid', N'East'),
            (3, N'Jordan Patel', N'jordan.patel@example.invalid', N'Central'),
            (4, N'Riley Nguyen', N'riley.nguyen@example.invalid', N'North'),
            (5, N'Casey Flores', N'casey.flores@example.invalid', N'South'),
            (6, N'Devon Brooks', N'devon.brooks@example.invalid', N'West')
        ) AS v(CustomerID, CustomerName, Email, SalesRegion)
        WHERE v.CustomerID = c.CustomerID
          AND v.CustomerName = c.CustomerName
          AND v.Email = c.Email
          AND v.SalesRegion = c.SalesRegion
    )
    OR
    (
        c.CustomerID BETWEEN 7 AND 120
        AND c.CustomerName = CONCAT(N'Demo Customer ', RIGHT(CONCAT(N'000', c.CustomerID), 3))
        AND c.Email = CONCAT(N'customer', RIGHT(CONCAT(N'000', c.CustomerID), 3), N'@example.invalid')
        AND c.SalesRegion = CASE (c.CustomerID - 1) % 5
            WHEN 0 THEN N'West' WHEN 1 THEN N'East' WHEN 2 THEN N'Central' WHEN 3 THEN N'North' ELSE N'South'
        END
    )
)
AND CONVERT(nvarchar(max), c.Preferences) = CONCAT(
    N'{"newsletter":', CASE WHEN c.CustomerID % 2 = 0 THEN N'false' ELSE N'true' END,
    N',"preferredCategory":"', CASE ((c.CustomerID - 1) % 10)
        WHEN 0 THEN N'Bikes' WHEN 1 THEN N'Components' WHEN 2 THEN N'Accessories' WHEN 3 THEN N'Clothing'
        WHEN 4 THEN N'Navigation' WHEN 5 THEN N'Maintenance' WHEN 6 THEN N'Safety' WHEN 7 THEN N'Training'
        WHEN 8 THEN N'Nutrition' ELSE N'Travel' END,
    N'","profile":{"experience":"', CASE c.CustomerID % 3 WHEN 0 THEN N'advanced' WHEN 1 THEN N'beginner' ELSE N'intermediate' END,
    N'","homeRegion":"', c.SalesRegion, N'"},"notifications":{"channels":["email","sms"],"quietHours":{"start":"21:00","end":"07:00"}},"savedSearches":["trail gear","seasonal offers"],"favoriteRideTypes":["trail","gravel"]}'
);
GO

UPDATE c
SET Preferences = CONCAT(
    N'{"newsletter":', CASE WHEN c.CustomerID % 2 = 0 THEN N'false' ELSE N'true' END,
    N',"preferredCategory":"', CASE ((c.CustomerID - 1) % 10)
        WHEN 0 THEN N'Bikes' WHEN 1 THEN N'Components' WHEN 2 THEN N'Accessories' WHEN 3 THEN N'Clothing'
        WHEN 4 THEN N'Navigation' WHEN 5 THEN N'Maintenance' WHEN 6 THEN N'Safety' WHEN 7 THEN N'Training'
        WHEN 8 THEN N'Nutrition' ELSE N'Travel' END,
    N'","profile":{"experience":"', CASE c.CustomerID % 3 WHEN 0 THEN N'advanced' WHEN 1 THEN N'beginner' ELSE N'intermediate' END,
    N'","homeRegion":"', c.SalesRegion, N'"},"notifications":{"channels":["email","sms"],"quietHours":{"start":"21:00","end":"07:00"}},"savedSearches":["trail gear","seasonal offers"],"favoriteRideTypes":["trail","gravel"]}'
)
FROM customer.Customers AS c
JOIN ops.BootstrapSeedRegistry AS ownership
    ON ownership.SeedEntity = N'Customer'
   AND ownership.SeedID = c.CustomerID;
GO

SET IDENTITY_INSERT sales.Orders ON;
;WITH e1(n) AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
numbers(n) AS
(
    SELECT TOP (794) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM e1 AS a CROSS JOIN e1 AS b CROSS JOIN e1 AS c
)
INSERT sales.Orders (OrderID, CustomerID, OrderDate, OrderStatus, ShippingMetadata)
OUTPUT N'Order', INSERTED.OrderID, N'2.1.0-seed-ownership'
    INTO ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
SELECT
    6 + n,
    ((6 + n - 1) % 120) + 1,
    DATEADD(day, -((6 + n) % 365), CONVERT(datetime2(0), N'2026-01-01T12:00:00')),
    CASE (6 + n) % 5
        WHEN 0 THEN N'Pending' WHEN 1 THEN N'Processing' WHEN 2 THEN N'Shipped' WHEN 3 THEN N'Delivered' ELSE N'Cancelled'
    END,
    N'{"carrier":"TrailExpress","priority":"standard","destination":{"country":"US"},"parcels":[{"sequence":1}]}'
FROM numbers
WHERE NOT EXISTS (SELECT 1 FROM sales.Orders AS o WHERE o.OrderID = 6 + numbers.n);
SET IDENTITY_INSERT sales.Orders OFF;
GO

INSERT ops.BootstrapSeedRegistry (SeedEntity, SeedID, SeedVersion)
SELECT N'Order', o.OrderID, N'2.1.0-seed-ownership'
FROM sales.Orders AS o
WHERE NOT EXISTS
(
    SELECT 1
    FROM ops.BootstrapSeedRegistry AS ownership
    WHERE ownership.SeedEntity = N'Order'
      AND ownership.SeedID = o.OrderID
)
AND
(
    /* Orders 1-6 originally use SYSUTCDATETIME(), so a legacy row cannot
       prove its original timestamp. New installations record them via OUTPUT;
       legacy migration accepts only the fully deterministic expanded range. */
    o.OrderID BETWEEN 7 AND 800
    AND o.CustomerID = ((o.OrderID - 1) % 120) + 1
    AND o.OrderDate = DATEADD(day, -(o.OrderID % 365), CONVERT(datetime2(0), N'2026-01-01T12:00:00'))
    AND o.OrderStatus = CASE o.OrderID % 5
        WHEN 0 THEN N'Pending' WHEN 1 THEN N'Processing' WHEN 2 THEN N'Shipped' WHEN 3 THEN N'Delivered' ELSE N'Cancelled'
    END
)
AND CONVERT(nvarchar(max), o.ShippingMetadata) = CONCAT(
    N'{"carrier":"', CASE WHEN o.OrderID % 2 = 0 THEN N'TrailExpress' ELSE N'RidgeLogistics' END,
    N'","priority":"', CASE WHEN o.OrderID % 4 = 0 THEN N'express' ELSE N'standard' END,
    N'","tracking":{"number":"AG', RIGHT(CONCAT(N'000000', o.OrderID), 6),
    N'","events":[{"status":"label-created","at":"2025-12-01T08:00:00Z"},{"status":"',
    CASE WHEN o.OrderStatus IN (N'Delivered', N'Shipped') THEN N'in-transit' ELSE N'pending' END,
    N'","at":"2025-12-02T08:00:00Z"}]},"destination":{"region":"',
    CASE (o.CustomerID - 1) % 5 WHEN 0 THEN N'West' WHEN 1 THEN N'East' WHEN 2 THEN N'Central' WHEN 3 THEN N'North' ELSE N'South' END,
    N'","deliveryInstructions":["leave at secure location","send delivery notification"]},"parcels":[{"sequence":1,"weightKg":',
    CONVERT(nvarchar(20), CONVERT(decimal(4,1), 1.0 + ((o.OrderID % 20) * 0.2))),
    N',"dimensionsCm":{"length":30,"width":20,"height":12}}]}'
);
GO

UPDATE o
SET ShippingMetadata = CONCAT(
    N'{"carrier":"', CASE WHEN o.OrderID % 2 = 0 THEN N'TrailExpress' ELSE N'RidgeLogistics' END,
    N'","priority":"', CASE WHEN o.OrderID % 4 = 0 THEN N'express' ELSE N'standard' END,
    N'","tracking":{"number":"AG', RIGHT(CONCAT(N'000000', o.OrderID), 6),
    N'","events":[{"status":"label-created","at":"2025-12-01T08:00:00Z"},{"status":"',
    CASE WHEN o.OrderStatus IN (N'Delivered', N'Shipped') THEN N'in-transit' ELSE N'pending' END,
    N'","at":"2025-12-02T08:00:00Z"}]},"destination":{"region":"',
    CASE (o.CustomerID - 1) % 5 WHEN 0 THEN N'West' WHEN 1 THEN N'East' WHEN 2 THEN N'Central' WHEN 3 THEN N'North' ELSE N'South' END,
    N'","deliveryInstructions":["leave at secure location","send delivery notification"]},"parcels":[{"sequence":1,"weightKg":',
    CONVERT(nvarchar(20), CONVERT(decimal(4, 1), 1.0 + ((o.OrderID % 20) * 0.2))),
    N',"dimensionsCm":{"length":30,"width":20,"height":12}}]}'
)
FROM sales.Orders AS o
JOIN ops.BootstrapSeedRegistry AS ownership
    ON ownership.SeedEntity = N'Order'
   AND ownership.SeedID = o.OrderID;
GO

INSERT sales.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
SELECT v.OrderID, v.ProductID, v.Quantity, p.UnitPrice
FROM (VALUES (1, 10, 1), (2, 6, 1), (3, 1, 1), (4, 8, 1), (5, 7, 1)) AS v(OrderID, ProductID, Quantity)
JOIN catalog.Products AS p ON p.ProductID = v.ProductID
WHERE NOT EXISTS
(
    SELECT 1 FROM sales.OrderItems AS oi WHERE oi.OrderID = v.OrderID AND oi.ProductID = v.ProductID
);
GO

;WITH e1(n) AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
numbers(n) AS
(
    SELECT TOP (794) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM e1 AS a CROSS JOIN e1 AS b CROSS JOIN e1 AS c
),
items AS
(
    SELECT 6 + n AS OrderID, line.LineNumber,
           (((6 + n) * 17 + line.LineNumber * 37 - 1) % 150) + 1 AS ProductID
    FROM numbers
    CROSS JOIN (VALUES (1),(2),(3)) AS line(LineNumber)
)
INSERT sales.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
SELECT items.OrderID, items.ProductID, 1 + (items.LineNumber % 2), p.UnitPrice
FROM items
JOIN catalog.Products AS p ON p.ProductID = items.ProductID
WHERE NOT EXISTS
(
    SELECT 1 FROM sales.OrderItems AS oi WHERE oi.OrderID = items.OrderID AND oi.ProductID = items.ProductID
);
GO

SET IDENTITY_INSERT customer.ProductReviews ON;
;WITH e1(n) AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
numbers(n) AS
(
    SELECT TOP (486) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM e1 AS a CROSS JOIN e1 AS b CROSS JOIN e1 AS c
)
INSERT customer.ProductReviews (ReviewID, ProductID, CustomerID, ReviewTitle, ReviewText, Rating, CreatedAtUtc)
SELECT
    14 + n,
    ((14 + n - 1) % 150) + 1,
    ((14 + n - 1) % 120) + 1,
    CONCAT(N'Deterministic field review ', RIGHT(CONCAT(N'000', 14 + n), 3)),
    CONCAT(N'Review ', 14 + n, N' documents repeatable AdventureGear evaluation data for JSON, relational, and analytics demonstrations.'),
    ((14 + n - 1) % 5) + 1,
    DATEADD(day, -(14 + n), CONVERT(datetime2(3), N'2026-01-01T00:00:00'))
FROM numbers
WHERE NOT EXISTS (SELECT 1 FROM customer.ProductReviews AS r WHERE r.ReviewID = 14 + numbers.n);
SET IDENTITY_INSERT customer.ProductReviews OFF;
GO

/* Refresh the environment marker timestamp so re-runs record the latest init.
   重新整理環境標記時間戳記，使重新執行記錄最新初始化時間。
   */
UPDATE ops.DemoEnvironment
SET UpdatedAtUtc = SYSUTCDATETIME()
WHERE DemoEnvironmentID = 1;
GO

PRINT N'AdventureGearAI demo initialization complete.';
GO
