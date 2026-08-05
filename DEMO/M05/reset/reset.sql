/*
    M05 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 5 security objects and returns Module 5
    to a NotStarted baseline. The canonical customer.Customers core is left
    intact.

    Module-owned objects removed (dependency-safe order):
      * security.CustomerRegionPolicy  (Row-Level Security policy)
      * security.fn_RegionFilter       (RLS predicate function)
      * AdventureGearMaskedReader      (contained demo user)
      * AdventureGearWestReader        (contained demo user)
      * AdventureGearPermissionReader  (contained object-permission demo user)
      * security.usp_GetSecureCustomer  (EXECUTE AS OWNER demo procedure)
      * security.SecureCustomers       (masked companion projection table)

    M05 has no downstream module dependents, so only M05 is reset.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    * 統一 AdventureGearAI 的模組 5 範圍重設：絕不刪除資料庫；只移除安全性物件並將 M05 還原為 NotStarted，保留標準客戶核心。
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
    RAISERROR(N'M05 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
    * 保護條件 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
*/
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M05 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned objects only (policy -> predicate -> users -> companion
   table). The canonical customer.Customers core is never dropped.
   * 只依相依安全順序清除模組擁有的物件；標準核心不會被刪除。
--------------------------------------------------------------------------- */
DROP SECURITY POLICY IF EXISTS security.CustomerRegionPolicy;
DROP PROCEDURE IF EXISTS security.usp_GetSecureCustomer;
DROP FUNCTION IF EXISTS security.fn_RegionFilter;
DROP USER IF EXISTS AdventureGearMaskedReader;
DROP USER IF EXISTS AdventureGearWestReader;
DROP USER IF EXISTS AdventureGearPermissionReader;
DROP TABLE IF EXISTS security.SecureCustomers;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 5 (no dependents).
   * 狀態重設僅影響註解中指定的模組及其相依模組。
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (5);
GO

SET NOEXEC OFF;
GO
PRINT N'M05 reset complete: security objects removed; M05 marked NotStarted.';
GO
