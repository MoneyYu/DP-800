/*
    M07 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 7 CI/CD project/runtime objects and
    returns Module 7 to a NotStarted baseline. The canonical core is left intact.
    The buildable SQL project artifact (M07/common/Dp800.Database) on disk is a
    separate CI/CD asset and is not affected by this database reset.

    Module-owned objects removed (dependency-safe order):
      * catalog.usp_LogInventoryChange (stored procedure)
      * catalog.InventoryChangeLog     (change-log table)
      * ops.DeploymentLog              (deployment-log table)

    M07 has no downstream module dependents, so only M07 is reset.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    M07 reset/reset.sql
    統一 AdventureGearAI 示範的模組範圍重設。它絕不卸除資料庫；只移除模組 7 的 CI/CD 專案/執行階段物件，並將模組 7 還原為 NotStarted 基準狀態。標準核心會保持不變。磁碟上的可建置 SQL 專案成品（M07/common/Dp800.Database）是另一項 CI/CD 資產，不受此資料庫重設影響。
    移除的模組專屬物件（相依性安全順序）：catalog.usp_LogInventoryChange（預存程序）、catalog.InventoryChangeLog（變更記錄資料表）、ops.DeploymentLog（部署記錄資料表）。
    M07 沒有下游模組相依項，因此只會重設 M07。
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
    RAISERROR(N'M07 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
   防護 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
   */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M07 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (procedure -> tables). The canonical
   catalog.Products core referenced by the change log is never dropped.
---------------------------------------------------------------------------
只拆除模組專屬物件（預存程序再資料表）。變更記錄所參考的標準 catalog.Products 核心絕不會被卸除。
*/
DROP PROCEDURE IF EXISTS catalog.usp_LogInventoryChange;
DROP TABLE IF EXISTS catalog.InventoryChangeLog;
DROP TABLE IF EXISTS ops.DeploymentLog;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 7 (no dependents).
---------------------------------------------------------------------------
狀態重設：只重設模組 7（沒有相依項）。
*/
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (7);
GO

SET NOEXEC OFF;
GO
PRINT N'M07 reset complete: CI/CD objects removed; M07 marked NotStarted.';
GO
