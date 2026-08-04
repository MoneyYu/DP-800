/*
    M06 local/01-plans-query-store-dmvs.sql

    Execution plans, a covering index, Query Store, and DMV inspection over the
    ops.PerformanceOrders workload in AdventureGearAI. The index creation is
    guarded, so the script is safe to re-run.
    * 在 AdventureGearAI 的 ops.PerformanceOrders 工作負載上檢查執行計畫、建立涵蓋索引、查詢 Query Store 與 DMV；索引建立有保護條件，可安全重跑。
*/
SET STATISTICS IO ON;

/* Pre-index query: a customer's recent orders (customer 3 exists in the core).
    * 建立索引前，查詢客戶 3 的近期訂單。
*/
SELECT OrderID, OrderDate, ProductID, Quantity, UnitPrice, OrderStatus
FROM ops.PerformanceOrders
WHERE CustomerID = 3
  AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME())
ORDER BY OrderDate DESC;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.PerformanceOrders') AND name = N'IX_PerformanceOrders_CustomerDate')
    CREATE INDEX IX_PerformanceOrders_CustomerDate
    ON ops.PerformanceOrders(CustomerID, OrderDate DESC)
    INCLUDE(ProductID, Quantity, UnitPrice, OrderStatus);

/* Post-index query: the covering index should be used now.
    * 建立索引後，應使用涵蓋索引。
*/
SELECT OrderID, OrderDate, ProductID, Quantity, UnitPrice, OrderStatus
FROM ops.PerformanceOrders
WHERE CustomerID = 3
  AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME())
ORDER BY OrderDate DESC;

SET STATISTICS IO OFF;

/* DMV inspection: the most expensive statements by average logical reads.
    * 透過 DMV 檢查平均邏輯讀取量最高的陳述式。
*/
SELECT TOP (5)
    qs.execution_count,
    qs.total_worker_time / NULLIF(qs.execution_count, 0) AS AverageCpuTime,
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AverageLogicalReads,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
          - qs.statement_start_offset) / 2) + 1) AS StatementText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY AverageLogicalReads DESC;

/* Query Store configuration for AdventureGearAI.
    * 檢查 AdventureGearAI 的 Query Store 設定。
*/
SELECT actual_state_desc, desired_state_desc, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;
GO
