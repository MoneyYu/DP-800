/*
    M09 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 9 embedding objects and returns Module 9
    to a NotStarted baseline. The canonical catalog/customer core the documents
    are built from is left intact.

    Module-owned objects removed (dependency-safe order):
      * AdventureGearEmbeddingModel  (Azure external model, feature/edition gated)
      * ai.VectorFeatureProbe        (transient local feature-detection probe)
      * ai.EmbeddingChunks           (generated embedding chunks)
      * ai.EmbeddingDocuments        (embedding source-document table)

    Dependency/staleness reset: M10 (vector search) and M11 (RAG) consume the M09
    embedding pipeline, so resetting M09 marks M10 and M11 stale (NotStarted) as
    well, clearing their timestamps and errors.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    M09 reset/reset.sql
    統一 AdventureGearAI 示範的模組範圍重設。它絕不卸除資料庫；只移除模組 9 的嵌入物件，並將模組 9 還原為 NotStarted 基準狀態。建立文件的標準 catalog/customer 核心會保持不變。
    移除的模組專屬物件（相依性安全順序）：AdventureGearEmbeddingModel（Azure 外部模型，受功能/版本限制）、ai.VectorFeatureProbe（暫存的本機功能偵測探查）、ai.EmbeddingDocuments（嵌入來源文件資料表）。
    相依性/過期狀態重設：M10（向量搜尋）和 M11（RAG）使用 M09 嵌入管線；因此重設 M09 也會將 M10 和 M11 標示為過期（NotStarted），並清除其時間戳記和錯誤。
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
    RAISERROR(N'M09 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
   防護 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
   */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M09 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown the Azure external model when the build exposes external models and
   one exists. Feature/edition gated, so failures for unsupported engines are
   swallowed (the azure-only model is never provisioned locally). The referenced
   managed-identity credential is created out of band and is never touched here.
---------------------------------------------------------------------------
當目前建置公開外部模型且模型存在時拆除 Azure 外部模型。這受功能/版本限制，因此不支援的引擎所產生的失敗會被忽略（僅 Azure 的模型絕不會在本機佈建）。所參考的受控識別認證會在頻外建立，且絕不在此處變更。
*/
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'AdventureGearEmbeddingModel')
        EXEC sys.sp_executesql N'DROP EXTERNAL MODEL AdventureGearEmbeddingModel;';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (208, 102, 195)
        PRINT N'M09 reset: external model teardown skipped (external models not supported or none present).';
    ELSE
        THROW;
END CATCH;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned tables (probe -> chunks -> embedding documents). The canonical
   catalog/customer core is never dropped.
---------------------------------------------------------------------------
拆除模組專屬資料表（探查再嵌入文件）。標準 catalog/customer 核心絕不會被卸除。
*/
DROP TABLE IF EXISTS ai.VectorFeatureProbe;
DROP TABLE IF EXISTS ai.EmbeddingChunks;
DROP TABLE IF EXISTS ai.EmbeddingDocuments;
GO

/* ---------------------------------------------------------------------------
   State reset: Module 9 plus its downstream dependents M10 and M11 (stale).
---------------------------------------------------------------------------
狀態重設：模組 9 及其下游相依項 M10 和 M11（過期）。
*/
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (9, 10, 11);
GO

SET NOEXEC OFF;
GO
PRINT N'M09 reset complete: embedding objects removed; M09/M10/M11 marked NotStarted.';
GO
