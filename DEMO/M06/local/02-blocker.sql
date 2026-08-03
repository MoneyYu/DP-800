BEGIN TRANSACTION;
UPDATE dbo.PerformanceOrders SET OrderStatus = N'Cancelled' WHERE OrderID = 1;
WAITFOR DELAY '00:00:20';
ROLLBACK;
GO
