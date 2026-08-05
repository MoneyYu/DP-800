/*
    M06 common/01-workload.sql

    Module 6 (Optimize database performance) workload for AdventureGearAI. It
    builds a larger read/write workload table (ops.PerformanceOrders) derived from
    the canonical catalog/customer core: every generated row references a real
    catalog.Products row (ProductID + UnitPrice) and a real customer.Customers
    row (CustomerID), amplified with a numbers generator to a size worth tuning.

    Idempotent: the table is dropped and rebuilt, and Query Store is enabled with
    a repeatable option set.
    * 模組 6 的 AdventureGearAI 效能最佳化工作負載建立衍生自標準 catalog、customer 核心的 ops.PerformanceOrders，並以可重複的選項啟用 Query Store。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @appLockResult int;
DECLARE @appLockHeld bit = 0;

BEGIN TRY
    /* Plan forcing and module reset use this same session lock. Hold it for
       the complete setup lifecycle so neither can observe a dropped or
       partially populated workload, nor a transient Query Store setting. */
    EXEC @appLockResult = sys.sp_getapplock
        @Resource = N'DP800.M06.QueryStoreRecovery',
        @LockMode = N'Exclusive',
        @LockOwner = N'Session',
        @LockTimeout = 60000;

    IF @appLockResult < 0
        THROW 51007, N'M06 workload setup could not acquire the Query Store recovery lock.', 1;

    SET @appLockHeld = 1;

    DROP TABLE IF EXISTS ops.PerformanceOrders;

    CREATE TABLE ops.PerformanceOrders
    (
        OrderID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_PerformanceOrders PRIMARY KEY,
        CustomerID int NOT NULL
            CONSTRAINT FK_PerformanceOrders_Customers REFERENCES customer.Customers(CustomerID),
        ProductID int NOT NULL
            CONSTRAINT FK_PerformanceOrders_Products REFERENCES catalog.Products(ProductID),
        OrderDate datetime2(0) NOT NULL,
        Quantity int NOT NULL CONSTRAINT CK_PerformanceOrders_Quantity CHECK (Quantity > 0),
        UnitPrice decimal(10,2) NOT NULL,
        OrderStatus nvarchar(20) NOT NULL
    );

    /* Amplify the canonical catalog/customer rows into a tunable workload.
       Each row maps to the full ProductID (1..150) and CustomerID (1..120)
       ranges, preserving valid foreign keys and scenario fidelity.
       * 將標準 catalog、customer 資料列擴增為可調校工作負載，同時維持外部索引鍵與情境一致性。 */
    ;WITH Numbers AS
    (
        SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
        FROM sys.all_objects AS a
        CROSS JOIN sys.all_objects AS b
    )
    INSERT ops.PerformanceOrders (CustomerID, ProductID, OrderDate, Quantity, UnitPrice, OrderStatus)
    SELECT
        cust.CustomerID,
        prod.ProductID,
        DATEADD(minute, -n.Number, SYSUTCDATETIME()),
        (n.Number % 5) + 1,
        prod.UnitPrice,
        CHOOSE((n.Number % 4) + 1, N'Pending', N'Processing', N'Shipped', N'Delivered')
    FROM Numbers AS n
    CROSS APPLY
    (
        SELECT ProductID, UnitPrice
        FROM catalog.Products
        WHERE ProductID = ((n.Number - 1) % 150) + 1
    ) AS prod
    CROSS APPLY
    (
        SELECT CustomerID
        FROM customer.Customers
        WHERE CustomerID = ((n.Number - 1) % 120) + 1
    ) AS cust;

    ALTER DATABASE CURRENT SET QUERY_STORE = ON
    (
        OPERATION_MODE = READ_WRITE,
        QUERY_CAPTURE_MODE = AUTO,
        WAIT_STATS_CAPTURE_MODE = ON
    );

    IF @appLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M06.QueryStoreRecovery',
            @LockOwner = N'Session';
END TRY
BEGIN CATCH
    IF @appLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M06.QueryStoreRecovery',
            @LockOwner = N'Session';
    THROW;
END CATCH;
GO

PRINT N'M06 performance workload created against AdventureGearAI (ops.PerformanceOrders).';
GO
