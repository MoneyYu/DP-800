/*
    M06 local/05-deadlock-session-a.sql  (INTERACTIVE — excluded from the runner manifest)

    Deadlock demo, session A. Run simultaneously with 06-deadlock-session-b.sql in
    a separate session; one session will be chosen as the deadlock victim.
    * 互動式死結示範，已排除於執行器資訊清單：工作階段 A 必須與另一個連線中的 06-deadlock-session-b.sql 同時執行，其中一個工作階段會成為死結犧牲者。
*/
SET DEADLOCK_PRIORITY LOW;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ops.PerformanceOrders SET Quantity = Quantity + 1 WHERE OrderID = 1;
    WAITFOR DELAY '00:00:05';
    UPDATE ops.PerformanceOrders SET Quantity = Quantity + 1 WHERE OrderID = 2;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS DeadlockResult;
END CATCH;
GO
