/*
    M10 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 10 search objects and returns Module 10
    to a NotStarted baseline. The canonical catalog/customer core the corpus is
    built from is left intact.

    Module-owned objects removed (dependency-safe order):
      * IX_AdventureGear_SearchVector    (DiskANN vector index, preview gated)
      * full-text index on search.SearchDocuments
      * AdventureGearSearchCatalog       (full-text catalog)
      * search.SearchDocuments           (search corpus table)

    Dependency/staleness reset: M11 (RAG) retrieves grounding context from the
    M10 search corpus, so resetting M10 marks M11 stale (NotStarted) as well,
    clearing its timestamps and errors.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    M10 reset/reset.sql
    統一 AdventureGearAI 示範的模組範圍重設。它絕不卸除資料庫；只移除模組 10 的搜尋物件，並將模組 10 還原為 NotStarted 基準狀態。建立語料庫的標準 catalog/customer 核心會保持不變。
    移除的模組專屬物件（相依性安全順序）：IX_AdventureGear_SearchVector（DiskANN 向量索引，受預覽版限制）、search.SearchDocuments 上的全文檢索索引、AdventureGearSearchCatalog（全文檢索目錄）、search.SearchDocuments（搜尋語料庫資料表）。
    相依性/過期狀態重設：M11（RAG）從 M10 搜尋語料庫取得接地內容；因此重設 M10 也會將 M11 標示為過期（NotStarted），並清除其時間戳記和錯誤。
    設計為透過 DEMO/scripts/Invoke-Dp800Sql.ps1 對 AdventureGearAI 執行；該工具會先執行唯讀 Assert-DemoDatabase.sql 防護。下方內嵌防護可為直接執行提供縱深防禦。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Guard 1: refuse to run against anything but AdventureGearAI.
   防護 1：拒絕在 AdventureGearAI 以外的任何資料庫執行。
   */
IF DB_NAME() <> N'AdventureGearAI'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'M10 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
   防護 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
   */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M10 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown the DiskANN vector index first (preview/edition gated, so failures on
   unsupported engines are swallowed; the index is azure-only and never created
   locally).
---------------------------------------------------------------------------
先拆除 DiskANN 向量索引（受預覽版/版本限制，因此不支援引擎上的失敗會被忽略；索引僅限 Azure，且絕不在本機建立）。
*/
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'search.SearchDocuments') AND name = N'IX_AdventureGear_SearchVector')
        EXEC sys.sp_executesql N'DROP INDEX IX_AdventureGear_SearchVector ON search.SearchDocuments;';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (208, 102, 195, 3701)
        PRINT N'M10 reset: vector index teardown skipped (vector index not supported or none present).';
    ELSE
        THROW;
END CATCH;
GO

/* ---------------------------------------------------------------------------
   Teardown the full-text surface and the corpus table. The canonical
   catalog/customer core is never dropped.
---------------------------------------------------------------------------
拆除全文檢索介面與語料庫資料表。標準 catalog/customer 核心絕不會被卸除。
*/
IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'search.SearchDocuments'))
    DROP FULLTEXT INDEX ON search.SearchDocuments;
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'AdventureGearSearchCatalog')
    DROP FULLTEXT CATALOG AdventureGearSearchCatalog;
DROP TABLE IF EXISTS search.SearchDocuments;
GO

/* ---------------------------------------------------------------------------
   State reset: Module 10 plus its downstream dependent M11 (stale).
---------------------------------------------------------------------------
狀態重設：模組 10 及其下游相依項 M11（過期）。
*/
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (10, 11);
GO

SET NOEXEC OFF;
GO
PRINT N'M10 reset complete: search objects removed; M10/M11 marked NotStarted.';
GO
