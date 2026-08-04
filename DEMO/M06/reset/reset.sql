/*
    M06 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 6 performance workload and returns Module
    6 to a NotStarted baseline. The canonical core is left intact.

    Module-owned objects removed:
      * ops.PerformanceOrders (and its covering index IX_PerformanceOrders_CustomerDate,
        dropped implicitly with the table)

    Query Store is a database-level setting that many later modules can also rely
    on; this reset intentionally leaves Query Store ENABLED and only removes the
    module's operational workload data. Disabling Query Store is a database-level
    concern handled by the full reset, not this module reset.

    M06 has no downstream module dependents, so only M06 is reset.

    Intended to run against AdventureGearAI via DEMO/scripts/Invoke-Dp800Sql.ps1,
    which executes the read-only Assert-DemoDatabase.sql guard first. The inline
    guard below is defence-in-depth for direct execution.
    * 統一 AdventureGearAI 的模組 6 範圍重設：絕不刪除資料庫；只移除效能工作負載並將 M06 還原為 NotStarted，保留標準核心與已啟用的 Query Store。
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
    RAISERROR(N'M06 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker.
    * 保護條件 2：沒有有效的 AdventureGearAI 環境標記時拒絕執行。
*/
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M06 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned workload only. Any plan forced by the manual M06
   Query Store demo is unforced before its workload table is removed. Query
   Store remains enabled at the database level.
   * 只依相依安全順序清除模組擁有的物件；標準核心不會被刪除。
--------------------------------------------------------------------------- */
DECLARE @M06QueryId bigint;
DECLARE @M06PlanId bigint;
DECLARE @M06PriorQueryCaptureMode nvarchar(60);
DECLARE @M06ExpectedDemoQueryCaptureMode nvarchar(60);
DECLARE @M06RecoveryPhase nvarchar(30);
DECLARE @M06CurrentQueryCaptureMode nvarchar(60);
DECLARE @M06RecoveryStateActive bit = 0;
DECLARE @M06UnforceCompleted bit = 1;
DECLARE @M06AppLockResult int;
DECLARE @M06AppLockHeld bit = 0;

BEGIN TRY
    EXEC @M06AppLockResult = sys.sp_getapplock
        @Resource = N'DP800.M06.QueryStoreRecovery',
        @LockMode = N'Exclusive',
        @LockOwner = N'Session',
        @LockTimeout = 60000;

    IF @M06AppLockResult < 0
        THROW 51007, N'M06 reset could not acquire the Query Store recovery lock.', 1;

    SET @M06AppLockHeld = 1;

    /* Hold the same lifecycle lock as the interactive demo from legacy-column
       migration through cleanup, so concurrent reset/demo sessions cannot race
       on the recovery table or overwrite a manually changed capture mode. */
    IF OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NOT NULL
    BEGIN
        IF COL_LENGTH(N'ops.M06QueryStoreRuntimeState', N'ExpectedDemoQueryCaptureMode') IS NULL
            ALTER TABLE ops.M06QueryStoreRuntimeState
                ADD ExpectedDemoQueryCaptureMode nvarchar(60) NULL;

        IF COL_LENGTH(N'ops.M06QueryStoreRuntimeState', N'RecoveryPhase') IS NULL
            ALTER TABLE ops.M06QueryStoreRuntimeState
                ADD RecoveryPhase nvarchar(30) NULL;

        /* A legacy row can gain these columns in this batch. Use dynamic SQL
           so the post-migration statements compile against the new schema. */
        EXEC sys.sp_executesql
            N'UPDATE ops.M06QueryStoreRuntimeState
              SET ExpectedDemoQueryCaptureMode = N''ALL'',
                  RecoveryPhase = N''Active''
              WHERE M06QueryStoreRuntimeStateID = 1
                AND ExpectedDemoQueryCaptureMode IS NULL
                AND RecoveryPhase IS NULL;';

        EXEC sys.sp_executesql
            N'SELECT
                  @PriorQueryCaptureMode = PriorQueryCaptureMode,
                  @ExpectedDemoQueryCaptureMode = ExpectedDemoQueryCaptureMode,
                  @RecoveryPhase = RecoveryPhase
              FROM ops.M06QueryStoreRuntimeState
              WHERE M06QueryStoreRuntimeStateID = 1;',
            N'@PriorQueryCaptureMode nvarchar(60) OUTPUT,
              @ExpectedDemoQueryCaptureMode nvarchar(60) OUTPUT,
              @RecoveryPhase nvarchar(30) OUTPUT',
            @PriorQueryCaptureMode = @M06PriorQueryCaptureMode OUTPUT,
            @ExpectedDemoQueryCaptureMode = @M06ExpectedDemoQueryCaptureMode OUTPUT,
            @RecoveryPhase = @M06RecoveryPhase OUTPUT;

        SET @M06RecoveryStateActive = CASE WHEN @M06RecoveryPhase = N'Active' THEN 1 ELSE 0 END;
    END;

    DECLARE M06ForcedPlanCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT q.query_id, p.plan_id
    FROM sys.query_store_query AS q
    INNER JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    WHERE qt.query_sql_text LIKE N'%DP800 M06 plan forcing probe%'
      AND p.is_forced_plan = 1;

    OPEN M06ForcedPlanCursor;
    FETCH NEXT FROM M06ForcedPlanCursor INTO @M06QueryId, @M06PlanId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC sys.sp_query_store_unforce_plan @query_id = @M06QueryId, @plan_id = @M06PlanId;
        END TRY
        BEGIN CATCH
            SET @M06UnforceCompleted = 0;
            PRINT CONCAT(N'M06 reset could not unforce Query Store plan ', @M06PlanId, N': ', ERROR_MESSAGE());
        END CATCH;

        FETCH NEXT FROM M06ForcedPlanCursor INTO @M06QueryId, @M06PlanId;
    END;
    CLOSE M06ForcedPlanCursor;
    DEALLOCATE M06ForcedPlanCursor;

    IF @M06UnforceCompleted = 0
        THROW 51004, N'M06 reset could not complete Query Store plan cleanup; recovery state was retained for a later retry.', 1;

    IF @M06RecoveryStateActive = 1
    BEGIN
        IF @M06PriorQueryCaptureMode NOT IN (N'ALL', N'AUTO', N'CUSTOM', N'NONE')
            THROW 51005, N'M06 reset found an invalid Query Store recovery capture mode; recovery state was retained.', 1;

        IF @M06ExpectedDemoQueryCaptureMode NOT IN (N'ALL', N'AUTO', N'CUSTOM', N'NONE')
            THROW 51006, N'M06 reset found an invalid expected Query Store recovery mode; recovery state was retained.', 1;

        /* Re-read immediately before ALTER DATABASE while holding the lock.
           A nonmatching mode is a stale record, not authority to undo a user's
           manual Query Store configuration. */
        SELECT @M06CurrentQueryCaptureMode = query_capture_mode_desc
        FROM sys.database_query_store_options;

        IF @M06CurrentQueryCaptureMode = @M06ExpectedDemoQueryCaptureMode
        BEGIN
            DECLARE @M06RestoreQueryCaptureMode nvarchar(max) =
                N'ALTER DATABASE CURRENT SET QUERY_STORE (QUERY_CAPTURE_MODE = ' + @M06PriorQueryCaptureMode + N');';
            EXEC sys.sp_executesql @M06RestoreQueryCaptureMode;
        END;
    END;

    IF OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NOT NULL
    BEGIN
        DELETE FROM ops.M06QueryStoreRuntimeState
        WHERE M06QueryStoreRuntimeStateID = 1;
    END;

    DROP TABLE IF EXISTS ops.PerformanceOrders;
    DROP TABLE IF EXISTS ops.M06QueryStoreRuntimeState;

    /* M06 has no downstream module dependents. Keep this state transition under
       the lifecycle lock so setup cannot observe a partial teardown. */
    UPDATE ops.DemoModuleState
    SET Status = N'NotStarted',
        StartedAtUtc = NULL,
        CompletedAtUtc = NULL,
        LastError = NULL,
        ErrorNumber = NULL,
        ErrorLine = NULL,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE ModuleNumber IN (6);
END TRY
BEGIN CATCH
    IF @M06AppLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M06.QueryStoreRecovery',
            @LockOwner = N'Session';
    THROW;
END CATCH;

IF @M06AppLockHeld = 1
    EXEC sys.sp_releaseapplock
        @Resource = N'DP800.M06.QueryStoreRecovery',
        @LockOwner = N'Session';
GO

SET NOEXEC OFF;
GO
PRINT N'M06 reset complete: performance workload removed (Query Store left enabled); M06 marked NotStarted.';
GO
