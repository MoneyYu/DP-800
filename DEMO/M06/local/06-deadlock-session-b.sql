BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.PerformanceOrders SET Quantity = Quantity + 1 WHERE OrderID = 2;
    WAITFOR DELAY '00:00:05';
    UPDATE dbo.PerformanceOrders SET Quantity = Quantity + 1 WHERE OrderID = 1;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS DeadlockResult;
END CATCH;
GO

