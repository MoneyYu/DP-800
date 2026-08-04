-- M04 reference improvement (AdventureGearAI).
-- M04 參考改良版本（AdventureGearAI）。
-- The reviewed/refactored form of 01-review-target.sql: explicit column list,
-- 這是 01-review-target.sql 經檢閱與重構後的形式：明確欄位清單、
-- ANSI joins, schema-qualified canonical objects, and a parameterized predicate.
-- ANSI 聯結、結構描述限定的標準物件，以及參數化述詞。
DECLARE @CustomerSearch nvarchar(100) = N'Lee';

SELECT
    o.OrderID,
    o.OrderDate,
    o.OrderStatus,
    c.CustomerName,
    i.ProductID,
    i.Quantity,
    i.UnitPrice
FROM sales.Orders AS o
INNER JOIN customer.Customers AS c ON c.CustomerID = o.CustomerID
INNER JOIN sales.OrderItems AS i ON i.OrderID = o.OrderID
WHERE c.CustomerName LIKE N'%' + @CustomerSearch + N'%'
ORDER BY o.OrderDate DESC;
GO
