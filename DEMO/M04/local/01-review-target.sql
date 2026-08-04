-- M04 review target (AdventureGearAI).
-- Trainer prompt: explain the risks, then rewrite this query using explicit
-- columns and ANSI joins. Intentionally poor input for an explain/review/refactor
-- exercise; it runs against the canonical AdventureGearAI sales/customer core.
SELECT *
FROM sales.Orders AS o, customer.Customers AS c, sales.OrderItems AS i
WHERE o.CustomerID = c.CustomerID
  AND i.OrderID = o.OrderID
  AND c.CustomerName LIKE N'%' + N'Lee' + N'%';
GO
