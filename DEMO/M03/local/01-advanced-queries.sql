/*
    M03 local/01-advanced-queries.sql

    Advanced T-SQL against AdventureGearAI: recursive CTE, window functions,
    relational and native-json OPENJSON shredding, JSON output and aggregation,
    SOUNDEX/DIFFERENCE fuzzy matching, SQL graph MATCH, runtime regular-expression
    feature detection, and structured error handling.
    Read-only apart from a self-rolling-back error-handling demonstration.
    * 在 AdventureGearAI 上示範遞迴 CTE、視窗函式、JSON、模糊比對、SQL 圖形、正則運算式功能偵測與結構化錯誤處理；除自行回復的示範外均為唯讀。
*/
SET NOCOUNT ON;
GO

/* Recursive CTE over the org-chart teaching object.
    * 對組織圖教學物件執行遞迴 CTE。
*/
;WITH Organization AS
(
    SELECT EmployeeID, ManagerID, EmployeeName, 0 AS Depth
    FROM ops.EmployeeHierarchy
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT child.EmployeeID, child.ManagerID, child.EmployeeName, parent.Depth + 1
    FROM ops.EmployeeHierarchy AS child
    INNER JOIN Organization AS parent ON child.ManagerID = parent.EmployeeID
)
SELECT EmployeeID, REPLICATE(N'  ', Depth) + EmployeeName AS OrganizationChart
FROM Organization
ORDER BY Depth, EmployeeID;

/* Window functions ranking canonical products within their category.
    * 使用視窗函式依類別為標準產品排名。
*/
SELECT
    cat.CategoryName,
    p.ProductName,
    p.UnitPrice,
    ROW_NUMBER() OVER (PARTITION BY cat.CategoryName ORDER BY p.UnitPrice DESC) AS PriceRank,
    SUM(p.UnitPrice) OVER (PARTITION BY cat.CategoryName) AS CategoryValue
FROM catalog.Products AS p
INNER JOIN catalog.Categories AS cat ON cat.CategoryID = p.CategoryID
ORDER BY cat.CategoryName, PriceRank;

/* OPENJSON shredding of a proposed price-update document.
    * 拆解建議調價文件中的 OPENJSON 資料。
*/
DECLARE @Updates nvarchar(max) = N'[{"ProductID":1,"NewPrice":1424.05},{"ProductID":5,"NewPrice":45.90}]';
SELECT ProductID, NewPrice
FROM OPENJSON(@Updates)
WITH (ProductID int '$.ProductID', NewPrice decimal(10,2) '$.NewPrice');

/* Customer order details as an API-ready JSON document. JSON_QUERY preserves
   the nested FOR JSON result as an array rather than escaping it as text.
   * 以 API 就緒 JSON 文件顯示每位客戶的訂單明細；JSON_QUERY 會保留巢狀陣列。
*/
SELECT
    c.CustomerID,
    c.CustomerName,
    JSON_QUERY
    (
        (
            SELECT
                o.OrderID,
                o.OrderDate,
                o.OrderStatus,
                JSON_QUERY
                (
                    (
                        SELECT oi.ProductID, p.ProductName, oi.Quantity, oi.UnitPrice
                        FROM sales.OrderItems AS oi
                        INNER JOIN catalog.Products AS p ON p.ProductID = oi.ProductID
                        WHERE oi.OrderID = o.OrderID
                        ORDER BY oi.OrderItemID
                        FOR JSON PATH
                    )
                ) AS Items
            FROM sales.Orders AS o
            WHERE o.CustomerID = c.CustomerID
            ORDER BY o.OrderDate DESC, o.OrderID DESC
            FOR JSON PATH
        )
    ) AS OrderDetailsJson
FROM customer.Customers AS c
WHERE EXISTS (SELECT 1 FROM sales.Orders AS o WHERE o.CustomerID = c.CustomerID)
ORDER BY c.CustomerID;

/* JSON_ARRAYAGG aggregates relational orders into one JSON array per customer.
   * 使用 JSON_ARRAYAGG 將關聯式訂單彙總成每位客戶的一個 JSON 陣列。
*/
SELECT
    c.CustomerID,
    c.CustomerName,
    JSON_ARRAYAGG
    (
        JSON_OBJECT
        (
            'OrderID': o.OrderID,
            'Status': o.OrderStatus,
            'OrderDate': o.OrderDate
        )
    ) AS OrderSummaryJson
FROM customer.Customers AS c
INNER JOIN sales.Orders AS o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerID, c.CustomerName
ORDER BY c.CustomerID;

/* OPENJSON can read a native json column directly, unlike the @Updates
   comparison above. It projects nested ProductMetadata attributes to rows.
   * OPENJSON 可直接讀取原生 json 欄位，並將巢狀 ProductMetadata 屬性投影成資料列。
*/
SELECT
    p.ProductID,
    p.ProductName,
    metadata.Terrain,
    metadata.Frame,
    metadata.TerrainTags
FROM catalog.Products AS p
CROSS APPLY OPENJSON(p.ProductMetadata)
WITH
(
    Terrain nvarchar(50) '$.terrain',
    Frame nvarchar(50) '$.frame',
    TerrainTags nvarchar(max) '$.compatibility.terrainTags' AS JSON
) AS metadata
WHERE p.ProductMetadata IS NOT NULL
ORDER BY p.ProductID;

/* This native-json predicate can use a JSON index on ProductMetadata when one
   is provisioned for the canonical column (for example, CREATE JSON INDEX).
   * 此原生 json 述詞在 canonical 欄位佈建 JSON 索引時可使用該索引。
*/
SELECT ProductID, ProductName, ProductMetadata
FROM catalog.Products
WHERE JSON_CONTAINS(ProductMetadata, N'trail', '$.compatibility.terrainTags[*]') = 1
ORDER BY ProductID;

/* Fuzzy matching of product names against a misspelled search term.
    * 以拼錯的搜尋字詞模糊比對產品名稱。
*/
SELECT ProductName, SOUNDEX(ProductName) AS SoundexCode,
       DIFFERENCE(ProductName, N'Puncture Guard Tyre') AS FuzzyScore
FROM catalog.Products
ORDER BY FuzzyScore DESC, ProductName;

/* SQL graph MATCH: employee -> manager reporting relationships.
    * 使用 SQL 圖形 MATCH 查詢匯報關係。
*/
SELECT employee.EmployeeName, manager.EmployeeName AS ManagerName
FROM ops.EmployeeNode AS employee,
     ops.ReportsTo AS relation,
     ops.EmployeeNode AS manager
WHERE MATCH(employee-(relation)->manager)
ORDER BY manager.EmployeeName, employee.EmployeeName;

/* Runtime feature detection for SQL Server 2025 regular-expression syntax over
   * 於執行階段偵測 SQL Server 2025 正則運算式語法是否可用。
   canonical customer email addresses. */
BEGIN TRY
    EXEC sys.sp_executesql N'
        SELECT CustomerName, Email
        FROM customer.Customers
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

/* Structured error handling with a rolled-back transaction.
    * 使用會回復交易的結構化錯誤處理。
*/
BEGIN TRY
    BEGIN TRANSACTION;
    THROW 51030, 'Demonstration error: transaction will be rolled back.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO
