/*
    M04 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. Module 4 (code review / refactoring) provisions NO persistent
    objects: its local scripts are read-only review-target and reference-improved
    queries against the canonical core. This reset therefore only returns Module 4
    to a NotStarted baseline. The canonical core is left intact.

    M04 has no downstream module dependents, so only M04 is reset.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    * 統一 AdventureGearAI 的模組 4 範圍重設：絕不刪除資料庫；M04 的程式碼檢閱與重構指令碼不建立持續性物件，因此只將其狀態還原為 NotStarted。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Guard 1: refuse to run against anything but AdventureGearAI.
    * 保護條件 1：拒絕在 AdventureGearAI 以外的資料庫執行。
*/
IF DB_NAME() <> N'AdventureGearAI'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'M04 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
    * 保護條件 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
*/
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M04 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Module 4 owns no persistent objects; there is nothing to drop. Only the
   module state is reset.
   * 此 SQL 註解區塊說明上述操作的用途、範圍與安全限制。
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (4);
GO

SET NOEXEC OFF;
GO
PRINT N'M04 reset complete: no objects to remove; M04 marked NotStarted.';
GO
