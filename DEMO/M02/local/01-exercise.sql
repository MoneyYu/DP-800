SELECT * FROM dbo.vw_CustomerOrderSummary ORDER BY OrderDate DESC;

DECLARE @OrderID int = (SELECT MIN(OrderID) FROM dbo.Orders);
DELETE dbo.OrderItems WHERE OrderID = @OrderID AND ProductID = 4;
EXEC dbo.usp_AddOrderItem @OrderID = @OrderID, @ProductID = 4, @Quantity = 1;
SELECT dbo.fn_OrderTotal(@OrderID) AS RecalculatedOrderTotal;

SELECT c.CustomerName, o.OrderID, o.OrderStatus
FROM dbo.Customers AS c
CROSS APPLY dbo.fn_CustomerOrders(c.CustomerID) AS o;

UPDATE dbo.Orders SET OrderStatus = N'Complete' WHERE OrderID = @OrderID;
SELECT * FROM dbo.OrderStatusAudit ORDER BY AuditID DESC;
GO
