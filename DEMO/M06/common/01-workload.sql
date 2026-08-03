SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS dbo.PerformanceOrders;

CREATE TABLE dbo.PerformanceOrders
(
    OrderID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_PerformanceOrders PRIMARY KEY,
    CustomerID int NOT NULL,
    ProductID int NOT NULL,
    OrderDate datetime2(0) NOT NULL,
    Quantity int NOT NULL,
    UnitPrice decimal(10,2) NOT NULL,
    OrderStatus nvarchar(20) NOT NULL
);

;WITH Numbers AS
(
    SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT dbo.PerformanceOrders (CustomerID, ProductID, OrderDate, Quantity, UnitPrice, OrderStatus)
SELECT
    (Number % 200) + 1,
    (Number % 4) + 1,
    DATEADD(minute, -Number, SYSUTCDATETIME()),
    (Number % 5) + 1,
    CAST(10 + (Number % 200) AS decimal(10,2)),
    CHOOSE((Number % 4) + 1, N'Pending', N'Processing', N'Shipped', N'Delivered')
FROM Numbers;

ALTER DATABASE CURRENT SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    WAIT_STATS_CAPTURE_MODE = ON
);
GO
