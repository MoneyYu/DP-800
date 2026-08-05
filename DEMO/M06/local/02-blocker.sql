/*
    M06 local/02-blocker.sql  (INTERACTIVE — excluded from the runner manifest)

    Session 1 of the blocking demo. Run manually in its own session; it holds a
    lock on ops.PerformanceOrders for 20 seconds, then rolls back.
    * 互動式阻塞示範，已排除於執行器資訊清單：工作階段 1 必須手動在自己的連線中執行，鎖定 ops.PerformanceOrders 20 秒後回復。
*/
BEGIN TRANSACTION;
UPDATE ops.PerformanceOrders SET OrderStatus = N'Cancelled' WHERE OrderID = 1;
WAITFOR DELAY '00:00:20';
ROLLBACK;
GO
