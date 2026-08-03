SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.ReportsTo', N'U') IS NOT NULL DROP TABLE dbo.ReportsTo;
IF OBJECT_ID(N'dbo.EmployeeNode', N'U') IS NOT NULL DROP TABLE dbo.EmployeeNode;
DROP TABLE IF EXISTS dbo.EmployeeHierarchy;

CREATE TABLE dbo.EmployeeHierarchy
(
    EmployeeID int NOT NULL CONSTRAINT PK_EmployeeHierarchy PRIMARY KEY,
    ManagerID int NULL,
    EmployeeName nvarchar(100) NOT NULL
);

INSERT dbo.EmployeeHierarchy (EmployeeID, ManagerID, EmployeeName) VALUES
    (1, NULL, N'Riley Director'),
    (2, 1, N'Casey Manager'),
    (3, 1, N'Drew Manager'),
    (4, 2, N'Taylor Developer'),
    (5, 2, N'Alex Analyst');

CREATE TABLE dbo.EmployeeNode
(
    EmployeeID int NOT NULL,
    EmployeeName nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE dbo.ReportsTo AS EDGE;

INSERT dbo.EmployeeNode (EmployeeID, EmployeeName)
SELECT EmployeeID, EmployeeName FROM dbo.EmployeeHierarchy;

INSERT dbo.ReportsTo ($from_id, $to_id)
SELECT employee.$node_id, manager.$node_id
FROM dbo.EmployeeNode AS employee
INNER JOIN dbo.EmployeeHierarchy AS hierarchy ON hierarchy.EmployeeID = employee.EmployeeID
INNER JOIN dbo.EmployeeNode AS manager ON manager.EmployeeID = hierarchy.ManagerID;
GO
