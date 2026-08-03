DECLARE @CustomerSearch nvarchar(100) = N'Lee';

SELECT
    o.OrderID,
    o.OrderDate,
    o.OrderStatus,
    c.CustomerName,
    i.ProductID,
    i.Quantity,
    i.UnitPrice
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c ON c.CustomerID = o.CustomerID
INNER JOIN dbo.OrderItems AS i ON i.OrderID = o.OrderID
WHERE c.CustomerName LIKE N'%' + @CustomerSearch + N'%'
ORDER BY o.OrderDate DESC;
GO
