/*
    M02 common/01-programmability.sql

    Module 2 (Implement programmability objects) for the unified AdventureGearAI
    demo. Every object lives in the sales domain schema and operates on the
    canonical sales/customer/catalog core created by the bootstrap.

    Objects provisioned here (idempotent via CREATE OR ALTER / guarded drops):
      * sales.OrderStatusAudit                 (audit sink table)
      * sales.vw_CustomerOrderSummary          (reporting view)
      * sales.fn_OrderTotal                    (scalar function)
      * sales.fn_CustomerOrders                (inline table-valued function)
      * sales.usp_AddOrderItem                 (transactional stored procedure)
      * sales.trg_OrderStatusAudit             (AFTER UPDATE trigger on sales.Orders)
    * 模組 2 在 AdventureGearAI 的 sales 結構描述建立可程式性物件，操作標準 sales、customer、catalog 核心；使用 CREATE OR ALTER 與受保護刪除提供等冪建立。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DROP TRIGGER IF EXISTS sales.trg_OrderStatusAudit;
DROP PROCEDURE IF EXISTS sales.usp_AddOrderItem;
DROP FUNCTION IF EXISTS sales.fn_OrderTotal;
DROP FUNCTION IF EXISTS sales.fn_CustomerOrders;
DROP VIEW IF EXISTS sales.vw_CustomerOrderSummary;
DROP TABLE IF EXISTS sales.OrderStatusAudit;
GO

CREATE TABLE sales.OrderStatusAudit
(
    AuditID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderStatusAudit PRIMARY KEY,
    OrderID int NOT NULL
        CONSTRAINT FK_OrderStatusAudit_Orders REFERENCES sales.Orders(OrderID),
    OldStatus nvarchar(20) NULL,
    NewStatus nvarchar(20) NULL,
    ChangedAt datetime2(0) NOT NULL CONSTRAINT DF_OrderStatusAudit_ChangedAt DEFAULT SYSUTCDATETIME()
);
GO

CREATE OR ALTER VIEW sales.vw_CustomerOrderSummary
AS
SELECT
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.OrderDate,
    o.OrderStatus,
    SUM(oi.Quantity * oi.UnitPrice) AS OrderTotal
FROM customer.Customers AS c
INNER JOIN sales.Orders AS o ON o.CustomerID = c.CustomerID
INNER JOIN sales.OrderItems AS oi ON oi.OrderID = o.OrderID
GROUP BY c.CustomerID, c.CustomerName, o.OrderID, o.OrderDate, o.OrderStatus;
GO

CREATE OR ALTER FUNCTION sales.fn_OrderTotal(@OrderID int)
RETURNS decimal(18,2)
AS
BEGIN
    DECLARE @Total decimal(18,2);
    SELECT @Total = SUM(Quantity * UnitPrice)
    FROM sales.OrderItems
    WHERE OrderID = @OrderID;
    RETURN COALESCE(@Total, 0);
END;
GO

CREATE OR ALTER FUNCTION sales.fn_CustomerOrders(@CustomerID int)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderDate, OrderStatus
    FROM sales.Orders
    WHERE CustomerID = @CustomerID
);
GO

CREATE OR ALTER PROCEDURE sales.usp_AddOrderItem
    @OrderID int,
    @ProductID int,
    @Quantity int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Quantity <= 0 THROW 51001, 'Quantity must be positive.', 1;
        IF NOT EXISTS (SELECT 1 FROM sales.Orders WHERE OrderID = @OrderID)
            THROW 51002, 'Order does not exist.', 1;

        INSERT sales.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
        SELECT @OrderID, ProductID, @Quantity, UnitPrice
        FROM catalog.Products
        WHERE ProductID = @ProductID;

        IF @@ROWCOUNT = 0 THROW 51003, 'Product does not exist.', 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER TRIGGER sales.trg_OrderStatusAudit
ON sales.Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT sales.OrderStatusAudit (OrderID, OldStatus, NewStatus)
    SELECT i.OrderID, d.OrderStatus, i.OrderStatus
    FROM inserted AS i
    INNER JOIN deleted AS d ON d.OrderID = i.OrderID
    WHERE i.OrderStatus <> d.OrderStatus;
END;
GO

PRINT N'M02 programmability objects created against AdventureGearAI (sales schema).';
GO
