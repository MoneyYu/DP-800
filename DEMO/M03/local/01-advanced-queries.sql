;WITH Organization AS
(
    SELECT EmployeeID, ManagerID, EmployeeName, 0 AS Depth
    FROM dbo.EmployeeHierarchy
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT child.EmployeeID, child.ManagerID, child.EmployeeName, parent.Depth + 1
    FROM dbo.EmployeeHierarchy AS child
    INNER JOIN Organization AS parent ON child.ManagerID = parent.EmployeeID
)
SELECT EmployeeID, REPLICATE(N'  ', Depth) + EmployeeName AS OrganizationChart
FROM Organization
ORDER BY Depth, EmployeeID;

SELECT
    p.Category,
    p.ProductName,
    p.UnitPrice,
    ROW_NUMBER() OVER (PARTITION BY p.Category ORDER BY p.UnitPrice DESC) AS PriceRank,
    SUM(p.UnitPrice) OVER (PARTITION BY p.Category) AS CategoryValue
FROM dbo.Products AS p;

DECLARE @Updates nvarchar(max) = N'[{"ProductID":1,"NewPrice":1424.05},{"ProductID":2,"NewPrice":59.50}]';
SELECT ProductID, NewPrice
FROM OPENJSON(@Updates)
WITH (ProductID int '$.ProductID', NewPrice decimal(10,2) '$.NewPrice');

SELECT ProductName, SOUNDEX(ProductName) AS SoundexCode, DIFFERENCE(ProductName, N'Puncture Guard Tyre') AS FuzzyScore
FROM dbo.Products;

SELECT employee.EmployeeName, manager.EmployeeName AS ManagerName
FROM dbo.EmployeeNode AS employee,
     dbo.ReportsTo AS relation,
     dbo.EmployeeNode AS manager
WHERE MATCH(employee-(relation)->manager);

BEGIN TRY
    EXEC sys.sp_executesql N'
        SELECT CustomerName, Email
        FROM dbo.Customers
        WHERE REGEXP_LIKE(Email, ''^[^@]+@[^@]+[.][^@]+$'');';
    PRINT N'REGEX: supported and executed.';
END TRY
BEGIN CATCH
    DECLARE @RegexErrorNumber int = ERROR_NUMBER();
    DECLARE @RegexError nvarchar(2048) = ERROR_MESSAGE();
    IF @RegexErrorNumber IN (102, 195)
        RAISERROR(N'REGEX: skipped because this engine/build does not accept REGEXP_LIKE: %s', 10, 1, @RegexError);
    ELSE
        THROW;
END CATCH;

BEGIN TRY
    BEGIN TRANSACTION;
    THROW 51030, 'Demonstration error: transaction will be rolled back.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO
