SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DROP TRIGGER IF EXISTS dbo.trg_OrderStatusAudit;
DROP PROCEDURE IF EXISTS dbo.usp_AddOrderItem;
DROP FUNCTION IF EXISTS dbo.fn_OrderTotal;
DROP FUNCTION IF EXISTS dbo.fn_CustomerOrders;
DROP VIEW IF EXISTS dbo.vw_CustomerOrderSummary;
DROP TABLE IF EXISTS dbo.OrderStatusAudit;
GO

CREATE TABLE dbo.OrderStatusAudit
(
    AuditID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderStatusAudit PRIMARY KEY,
    OrderID int NOT NULL,
    OldStatus nvarchar(20) NULL,
    NewStatus nvarchar(20) NULL,
    ChangedAt datetime2(0) NOT NULL CONSTRAINT DF_OrderStatusAudit_ChangedAt DEFAULT SYSUTCDATETIME()
);
GO

CREATE OR ALTER VIEW dbo.vw_CustomerOrderSummary
AS
SELECT
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.OrderDate,
    o.OrderStatus,
    SUM(oi.Quantity * oi.UnitPrice) AS OrderTotal
FROM dbo.Customers AS c
INNER JOIN dbo.Orders AS o ON o.CustomerID = c.CustomerID
INNER JOIN dbo.OrderItems AS oi ON oi.OrderID = o.OrderID
GROUP BY c.CustomerID, c.CustomerName, o.OrderID, o.OrderDate, o.OrderStatus;
GO

CREATE OR ALTER FUNCTION dbo.fn_OrderTotal(@OrderID int)
RETURNS decimal(18,2)
AS
BEGIN
    DECLARE @Total decimal(18,2);
    SELECT @Total = SUM(Quantity * UnitPrice)
    FROM dbo.OrderItems
    WHERE OrderID = @OrderID;
    RETURN COALESCE(@Total, 0);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CustomerOrders(@CustomerID int)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderDate, OrderStatus
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID
);
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddOrderItem
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
        IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderID = @OrderID)
            THROW 51002, 'Order does not exist.', 1;

        INSERT dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
        SELECT @OrderID, ProductID, @Quantity, UnitPrice
        FROM dbo.Products
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

CREATE OR ALTER TRIGGER dbo.trg_OrderStatusAudit
ON dbo.Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.OrderStatusAudit (OrderID, OldStatus, NewStatus)
    SELECT i.OrderID, d.OrderStatus, i.OrderStatus
    FROM inserted AS i
    INNER JOIN deleted AS d ON d.OrderID = i.OrderID
    WHERE i.OrderStatus <> d.OrderStatus;
END;
GO
