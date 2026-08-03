-- Trainer prompt: explain the risks, then rewrite this query using explicit columns and joins.
SELECT *
FROM dbo.Orders AS o, dbo.Customers AS c, dbo.OrderItems AS i
WHERE o.CustomerID = c.CustomerID
  AND i.OrderID = o.OrderID
  AND c.CustomerName LIKE N'%' + N'Lee' + N'%';
GO

