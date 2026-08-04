/*
    M06 local/03-blocked.sql  (INTERACTIVE — excluded from the runner manifest)

    Session 2 of the blocking demo. Run manually while 02-blocker.sql holds its
    lock; this statement waits until the blocker rolls back.
    * 互動式阻塞示範，已排除於執行器資訊清單：工作階段 2 必須在 02-blocker.sql 持有鎖定時，手動於另一個連線中執行並等待阻塞者回復。
*/
UPDATE ops.PerformanceOrders SET OrderStatus = N'Shipped' WHERE OrderID = 1;
GO
