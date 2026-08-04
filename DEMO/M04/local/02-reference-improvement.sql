-- M04 reference improvement (AdventureGearAI).
-- The reviewed/refactored form of 01-review-target.sql: explicit column list,
-- ANSI joins, schema-qualified canonical objects, and a parameterized predicate.
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
