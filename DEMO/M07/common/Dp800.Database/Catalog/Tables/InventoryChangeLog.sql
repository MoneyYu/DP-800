CREATE TABLE [catalog].[InventoryChangeLog]
(
    [LogID] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_InventoryChangeLog] PRIMARY KEY,
    [ProductID] int NOT NULL,
    [ChangeDate] datetime2(0) NOT NULL CONSTRAINT [DF_InventoryChangeLog_ChangeDate] DEFAULT SYSUTCDATETIME(),
    [QuantityChange] int NOT NULL,
    [ChangeType] nvarchar(20) NOT NULL,
    [Notes] nvarchar(200) NULL
);
