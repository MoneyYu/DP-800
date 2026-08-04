/*
    M06 local/02-blocker.sql  (INTERACTIVE — excluded from the runner manifest)

    Session 1 of the blocking demo. Run manually in its own session; it holds a
    lock on ops.PerformanceOrders for 20 seconds, then rolls back.
*/
BEGIN TRANSACTION;
UPDATE ops.PerformanceOrders SET OrderStatus = N'Cancelled' WHERE OrderID = 1;
WAITFOR DELAY '00:00:20';
ROLLBACK;
GO
