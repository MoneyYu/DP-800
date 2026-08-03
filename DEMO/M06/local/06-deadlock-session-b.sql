/*
    M06 local/06-deadlock-session-b.sql  (INTERACTIVE — excluded from the runner manifest)

    Deadlock demo, session B. Run simultaneously with 05-deadlock-session-a.sql in
    a separate session; the two sessions acquire locks in the opposite order.
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
