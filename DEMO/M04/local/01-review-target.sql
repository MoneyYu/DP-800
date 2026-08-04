-- M04 review target (AdventureGearAI).
-- M04 檢閱目標（AdventureGearAI）。
-- Trainer prompt: explain the risks, then rewrite this query using explicit
-- 講師提示：先說明風險，再使用明確指定的
-- columns and ANSI joins. Intentionally poor input for an explain/review/refactor
-- 欄位與 ANSI 聯結重寫此查詢。這是刻意不佳的說明、檢閱與重構
-- exercise; it runs against the canonical AdventureGearAI sales/customer core.
-- 練習輸入；它會針對標準 AdventureGearAI sales/customer 核心執行。
SELECT *
FROM sales.Orders AS o, customer.Customers AS c, sales.OrderItems AS i
WHERE o.CustomerID = c.CustomerID
  AND i.OrderID = o.OrderID
  AND c.CustomerName LIKE N'%' + N'Lee' + N'%';
GO
