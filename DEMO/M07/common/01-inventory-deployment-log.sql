/*
    M07 common setup — CI/CD demo objects for AdventureGearAI.

    The dependency-aware module runner provisions M07 by executing this
    idempotent script against the single AdventureGearAI database. It creates the
    same catalog/ops objects that the SDK-style SQL project (common/Dp800.Database)
    builds into a dacpac, so the runner has real work to mark M07 Completed while
    the SQL project remains the buildable CI/CD artifact demonstrated separately
    via local/Build-SqlProject.ps1 and azure/build-deploy.yml.

    The catalog and ops schemas are created by the AdventureGearAI core
    bootstrap; this script only adds the module objects and is safe to re-run.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

IF OBJECT_ID(N'catalog.InventoryChangeLog', N'U') IS NULL
BEGIN
    CREATE TABLE catalog.InventoryChangeLog
    (
        LogID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_InventoryChangeLog PRIMARY KEY,
        ProductID int NOT NULL
            CONSTRAINT FK_InventoryChangeLog_Products REFERENCES catalog.Products(ProductID),
        ChangeDate datetime2(0) NOT NULL
            CONSTRAINT DF_InventoryChangeLog_ChangeDate DEFAULT SYSUTCDATETIME(),
        QuantityChange int NOT NULL,
        ChangeType nvarchar(20) NOT NULL,
        Notes nvarchar(200) NULL
    );
END;
GO

IF OBJECT_ID(N'ops.DeploymentLog', N'U') IS NULL
BEGIN
    CREATE TABLE ops.DeploymentLog
    (
        DeploymentID int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_DeploymentLog PRIMARY KEY,
        ReleaseTag nvarchar(60) NOT NULL,
        DeployedAtUtc datetime2(3) NOT NULL
            CONSTRAINT DF_DeploymentLog_DeployedAtUtc DEFAULT SYSUTCDATETIME(),
        DeployedBy nvarchar(128) NOT NULL
            CONSTRAINT DF_DeploymentLog_DeployedBy DEFAULT SUSER_SNAME(),
        Notes nvarchar(400) NULL
    );
END;
GO

CREATE OR ALTER PROCEDURE catalog.usp_LogInventoryChange
    @ProductID int,
    @QuantityChange int,
    @ChangeType nvarchar(20),
    @Notes nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT catalog.InventoryChangeLog (ProductID, QuantityChange, ChangeType, Notes)
    VALUES (@ProductID, @QuantityChange, @ChangeType, @Notes);
END;
GO

/* Record this provisioning as a deployment so the CI/CD log is never empty. */
INSERT ops.DeploymentLog (ReleaseTag, Notes)
VALUES (N'M07-setup', N'AdventureGearAI SQL project objects provisioned by the unified demo runner.');
GO

PRINT N'M07 CI/CD demo objects are ready in AdventureGearAI.';
GO
