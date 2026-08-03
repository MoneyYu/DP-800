CREATE PROCEDURE [dbo].[usp_LogInventoryChange]
    @ProductID int,
    @QuantityChange int,
    @ChangeType nvarchar(20),
    @Notes nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT dbo.InventoryLog (ProductID, QuantityChange, ChangeType, Notes)
    VALUES (@ProductID, @QuantityChange, @ChangeType, @Notes);
END;
