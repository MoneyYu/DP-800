/*
    M06 local/01-plans-query-store-dmvs.sql

    Execution plans, a covering index, Query Store, and DMV inspection over the
    ops.PerformanceOrders workload in AdventureGearAI. The index creation is
    guarded, so the script is safe to re-run.
*/
SET STATISTICS IO ON;

/* Pre-index query: a customer's recent orders (customer 3 exists in the core). */
SELECT OrderID, OrderDate, ProductID, Quantity, UnitPrice, OrderStatus
FROM ops.PerformanceOrders
WHERE CustomerID = 3
  AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME())
ORDER BY OrderDate DESC;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.PerformanceOrders') AND name = N'IX_PerformanceOrders_CustomerDate')
    CREATE INDEX IX_PerformanceOrders_CustomerDate
    ON ops.PerformanceOrders(CustomerID, OrderDate DESC)
    INCLUDE(ProductID, Quantity, UnitPrice, OrderStatus);

/* Post-index query: the covering index should be used now. */
SELECT OrderID, OrderDate, ProductID, Quantity, UnitPrice, OrderStatus
FROM ops.PerformanceOrders
WHERE CustomerID = 3
  AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME())
ORDER BY OrderDate DESC;

SET STATISTICS IO OFF;

/* DMV inspection: the most expensive statements by average logical reads. */
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

/* Query Store configuration for AdventureGearAI. */
SELECT actual_state_desc, desired_state_desc, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;
GO
