/*
    M03 common/01-advanced-objects.sql

    Module 3 (Write advanced T-SQL) teaching objects for AdventureGearAI. The
    recursive-hierarchy and graph demos use a self-contained org-chart teaching
    object in the ops schema (it is not a business entity, so it does not belong
    in catalog/sales/customer). The advanced queries in local/ combine this
    object with the canonical catalog/customer core.

    Idempotent: guarded drops recreate the module-owned objects on every run.
    * 模組 3 的 AdventureGearAI 進階 T-SQL 教學物件，使用 ops 結構描述中的自足組織圖；每次執行都會受保護地重建本模組物件。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.ReportsTo', N'U') IS NOT NULL DROP TABLE ops.ReportsTo;
IF OBJECT_ID(N'ops.EmployeeNode', N'U') IS NOT NULL DROP TABLE ops.EmployeeNode;
DROP TABLE IF EXISTS ops.EmployeeHierarchy;
GO

CREATE TABLE ops.EmployeeHierarchy
(
    EmployeeID int NOT NULL CONSTRAINT PK_EmployeeHierarchy PRIMARY KEY,
    ManagerID int NULL
        CONSTRAINT FK_EmployeeHierarchy_Manager REFERENCES ops.EmployeeHierarchy(EmployeeID),
    EmployeeName nvarchar(100) NOT NULL
);

INSERT ops.EmployeeHierarchy (EmployeeID, ManagerID, EmployeeName) VALUES
    (1, NULL, N'Riley Director'),
    (2, 1, N'Casey Manager'),
    (3, 1, N'Drew Manager'),
    (4, 2, N'Taylor Developer'),
    (5, 2, N'Alex Analyst');

CREATE TABLE ops.EmployeeNode
(
    EmployeeID int NOT NULL,
    EmployeeName nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE ops.ReportsTo AS EDGE;

INSERT ops.EmployeeNode (EmployeeID, EmployeeName)
SELECT EmployeeID, EmployeeName FROM ops.EmployeeHierarchy;

INSERT ops.ReportsTo ($from_id, $to_id)
SELECT employee.$node_id, manager.$node_id
FROM ops.EmployeeNode AS employee
INNER JOIN ops.EmployeeHierarchy AS hierarchy ON hierarchy.EmployeeID = employee.EmployeeID
INNER JOIN ops.EmployeeNode AS manager ON manager.EmployeeID = hierarchy.ManagerID;
GO

PRINT N'M03 advanced teaching objects created against AdventureGearAI (ops schema).';
GO
