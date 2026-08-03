CREATE TABLE [dbo].[InventoryLog]
(
    [LogID] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_InventoryLog] PRIMARY KEY,
    [ProductID] int NOT NULL,
    [ChangeDate] datetime2(0) NOT NULL CONSTRAINT [DF_InventoryLog_ChangeDate] DEFAULT SYSUTCDATETIME(),
    [QuantityChange] int NOT NULL,
    [ChangeType] nvarchar(20) NOT NULL,
    [Notes] nvarchar(200) NULL
);
