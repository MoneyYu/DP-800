/*
    M06 local/06-deadlock-session-b.sql  (INTERACTIVE — excluded from the runner manifest)

    Deadlock demo, session B. Run simultaneously with 05-deadlock-session-a.sql in
    a separate session; the two sessions acquire locks in the opposite order.
    * 互動式死結示範，已排除於執行器資訊清單：工作階段 B 必須與另一個連線中的 05-deadlock-session-a.sql 同時執行，兩個工作階段會以相反順序取得鎖定。
*/
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ops.PerformanceOrders SET Quantity = Quantity + 1 WHERE OrderID = 2;
    WAITFOR DELAY '00:00:05';
    UPDATE ops.PerformanceOrders SET Quantity = Quantity + 1 WHERE OrderID = 1;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS DeadlockResult;
END CATCH;
GO
