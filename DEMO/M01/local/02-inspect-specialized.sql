/*
    M01 local/02-inspect-specialized.sql

    Read-only inspection for M01 specialized tables. It never reads external
    data; it reports whether PolyBase metadata was created or truthfully skipped.
*/
SET NOCOUNT ON;
GO

/* Native JSON index metadata and the module-owned .modify() teaching row. */
SELECT ji.name AS JsonIndexName,
       ji.object_id,
       ji.index_id,
       ji.optimize_for_array_search
FROM sys.json_indexes AS ji
WHERE ji.object_id = OBJECT_ID(N'catalog.Products')
  AND ji.name = N'IX_Products_ProductMetadata';

SELECT ProductJsonTeachingID,
       JSON_VALUE(Payload, '$.lesson') AS Lesson,
       JSON_PATH_EXISTS(Payload, '$.topic') AS HasTopic
FROM catalog.ProductJsonTeaching;
GO

/* In-Memory OLTP is conditional on the engine capability. */
SELECT CONVERT(int, SERVERPROPERTY('IsXTPSupported')) AS IsXTPSupported,
       t.name AS MemoryOptimizedTable,
       t.is_memory_optimized,
       fg.name AS MemoryOptimizedFilegroup
FROM sys.filegroups AS fg
LEFT JOIN sys.tables AS t
    ON t.object_id = OBJECT_ID(N'catalog.ProductCacheInMemory')
WHERE fg.name = N'M01MemoryOptimized'
   OR t.object_id = OBJECT_ID(N'catalog.ProductCacheInMemory');
GO

/* Ledger system history and generated ledger view are engine-managed. */
SELECT currentTable.name AS LedgerTable,
       currentTable.ledger_type_desc AS LedgerType,
       historyTable.name AS LedgerHistoryTable,
       ledgerView.name AS LedgerView
FROM sys.tables AS currentTable
LEFT JOIN sys.tables AS historyTable
    ON historyTable.object_id = currentTable.history_table_id
LEFT JOIN sys.views AS ledgerView
    ON ledgerView.object_id = currentTable.ledger_view_id
WHERE currentTable.object_id = OBJECT_ID(N'ops.InventoryLedger');
GO

SELECT name AS SequenceName,
       start_value,
       increment,
       current_value
FROM sys.sequences
WHERE object_id = OBJECT_ID(N'catalog.ProductSkuSequence');

SELECT ProductSkuSequenceDemoID, AllocatedSkuNumber
FROM catalog.ProductSkuSequenceDemo
ORDER BY ProductSkuSequenceDemoID;
GO

/* PolyBase capability and metadata only; never SELECT from external data. */
SELECT CONVERT(int, SERVERPROPERTY('IsPolyBaseInstalled')) AS IsPolyBaseInstalled,
       CASE WHEN CONVERT(int, SERVERPROPERTY('IsPolyBaseInstalled')) = 1
            THEN N'External metadata should be present; this script does not query external data.'
            ELSE N'External metadata was skipped because PolyBase is unavailable.'
       END AS ExternalTableStatus;

SELECT et.name AS ExternalTableName,
       eds.name AS ExternalDataSourceName,
       eff.name AS ExternalFileFormatName
FROM sys.external_tables AS et
LEFT JOIN sys.external_data_sources AS eds
    ON eds.data_source_id = et.data_source_id
LEFT JOIN sys.external_file_formats AS eff
    ON eff.file_format_id = et.file_format_id
WHERE et.object_id = OBJECT_ID(N'catalog.ProductMetadataExternal');
GO
