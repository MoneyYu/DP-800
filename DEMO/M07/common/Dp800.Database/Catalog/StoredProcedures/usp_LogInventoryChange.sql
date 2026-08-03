CREATE PROCEDURE [catalog].[usp_LogInventoryChange]
    @ProductID int,
    @QuantityChange int,
    @ChangeType nvarchar(20),
    @Notes nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT [catalog].[InventoryChangeLog] (ProductID, QuantityChange, ChangeType, Notes)
    VALUES (@ProductID, @QuantityChange, @ChangeType, @Notes);
END;
