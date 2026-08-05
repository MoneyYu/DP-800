/*
    M02 local/01-exercise.sql

    Exercises the Module 2 programmability objects against the canonical sales
    data. The mutating portion runs inside an explicit transaction that is rolled
    back at the end, so the canonical AdventureGearAI data stays pristine and the
    module is safe to re-run through the runner (idempotent).
    * 練習模組 2 可程式性物件；變更資料的部分會在明確交易中執行並回復，因此標準 AdventureGearAI 資料不變且可安全重跑。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Reporting view over canonical customers/orders/order items (read-only).
    * 透過標準客戶、訂單及訂單明細的報表檢視進行唯讀查詢。
*/
SELECT * FROM sales.vw_CustomerOrderSummary ORDER BY OrderDate DESC;
GO

BEGIN TRANSACTION;

/* Add a line item to an existing order via the transactional procedure, then
   * 使用交易式程序將明細加入既有訂單，再用純量函式重新計算訂單總額。
   recalculate the order total with the scalar function. */
DECLARE @OrderID int = (SELECT MIN(OrderID) FROM sales.Orders);
EXEC sales.usp_AddOrderItem @OrderID = @OrderID, @ProductID = 5, @Quantity = 1;
SELECT sales.fn_OrderTotal(@OrderID) AS RecalculatedOrderTotal;

/* Inline TVF fan-out: every customer's orders.
    * 使用內嵌資料表值函式展開每位客戶的訂單。
*/
SELECT c.CustomerName, o.OrderID, o.OrderStatus
FROM customer.Customers AS c
CROSS APPLY sales.fn_CustomerOrders(c.CustomerID) AS o
ORDER BY c.CustomerName, o.OrderID;

/* Change an order status to a valid canonical value so the audit trigger fires.
    * 變更訂單狀態以觸發稽核觸發程序。
*/
UPDATE sales.Orders SET OrderStatus = N'Shipped'
WHERE OrderID = (SELECT MIN(OrderID) FROM sales.Orders WHERE OrderStatus = N'Processing');
SELECT * FROM sales.OrderStatusAudit ORDER BY AuditID DESC;

/* Roll everything back: the demo objects are proven without mutating the core.
    * 回復所有變更，驗證示範物件而不變更核心。
*/
ROLLBACK;
GO
