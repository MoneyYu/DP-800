/*
    M06 local/03-blocked.sql  (INTERACTIVE — excluded from the runner manifest)

    Session 2 of the blocking demo. Run manually while 02-blocker.sql holds its
    lock; this statement waits until the blocker rolls back.
*/
UPDATE ops.PerformanceOrders SET OrderStatus = N'Shipped' WHERE OrderID = 1;
GO
