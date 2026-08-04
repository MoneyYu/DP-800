/*
    M02 local/01-exercise.sql

    Exercises the Module 2 programmability objects against the canonical sales
    data. The mutating portion runs inside an explicit transaction that is rolled
    back at the end, so the canonical AdventureGearAI data stays pristine and the
    module is safe to re-run through the runner (idempotent).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Reporting view over canonical customers/orders/order items (read-only). */
SELECT * FROM sales.vw_CustomerOrderSummary ORDER BY OrderDate DESC;
GO

BEGIN TRANSACTION;

/* Add a line item to an existing order via the transactional procedure, then
   recalculate the order total with the scalar function. */
DECLARE @OrderID int = (SELECT MIN(OrderID) FROM sales.Orders);
EXEC sales.usp_AddOrderItem @OrderID = @OrderID, @ProductID = 5, @Quantity = 1;
SELECT sales.fn_OrderTotal(@OrderID) AS RecalculatedOrderTotal;

/* Inline TVF fan-out: every customer's orders. */
SELECT c.CustomerName, o.OrderID, o.OrderStatus
FROM customer.Customers AS c
CROSS APPLY sales.fn_CustomerOrders(c.CustomerID) AS o
ORDER BY c.CustomerName, o.OrderID;

/* Change an order status to a valid canonical value so the audit trigger fires. */
UPDATE sales.Orders SET OrderStatus = N'Shipped'
WHERE OrderID = (SELECT MIN(OrderID) FROM sales.Orders WHERE OrderStatus = N'Processing');
SELECT * FROM sales.OrderStatusAudit ORDER BY AuditID DESC;

/* Roll everything back: the demo objects are proven without mutating the core. */
ROLLBACK;
GO
