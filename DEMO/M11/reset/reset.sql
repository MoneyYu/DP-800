/*
    M11 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 11 RAG stored procedures and returns
    Module 11 to a NotStarted baseline. The M10 search corpus and canonical core
    are left intact.

    Module-owned objects removed:
      * ai.usp_AskProductQuestion (Azure RAG procedure, azure-only)
      * ai.usp_BuildRagPrompt     (local RAG prompt-builder procedure)

    M11 is the leaf of the dependency chain (no downstream dependents), so only
    M11 is reset.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    M11 reset/reset.sql
    統一 AdventureGearAI 示範的模組範圍重設。它絕不卸除資料庫；只移除模組 11 的 RAG 預存程序，並將模組 11 還原為 NotStarted 基準狀態。M10 搜尋語料庫與標準核心會保持不變。
    移除的模組專屬物件：ai.usp_AskProductQuestion（Azure RAG 預存程序，僅 Azure）、ai.usp_BuildRagPrompt（本機 RAG 提示建立器預存程序）。
    M11 是相依鏈的葉節點（沒有下游相依項），因此只會重設 M11。
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
    RAISERROR(N'M11 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
   防護 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
   */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M11 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned procedures only. The M10 search corpus (search schema)
   and the canonical core are never dropped.
---------------------------------------------------------------------------
只拆除模組專屬預存程序。M10 搜尋語料庫（search 結構描述）和標準核心絕不會被卸除。
*/
DROP PROCEDURE IF EXISTS ai.usp_AskProductQuestion;
DROP PROCEDURE IF EXISTS ai.usp_BuildRagPrompt;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 11 (leaf; no dependents).
---------------------------------------------------------------------------
狀態重設：只重設模組 11（葉節點；沒有相依項）。
*/
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (11);
GO

SET NOEXEC OFF;
GO
PRINT N'M11 reset complete: RAG procedures removed; M11 marked NotStarted.';
GO
