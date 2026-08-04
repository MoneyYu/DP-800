/*
    M06 local/08-query-store-plan-forcing.sql (INTERACTIVE — excluded from runner)

    Captures an unindexed and indexed version of one stable query, then forces
    one captured plan only when Query Store has two or more plans. The script
    always unforces the plan it forced and restores the Query Store capture mode
    that was active before the demo.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.PerformanceOrders', N'U') IS NULL
    THROW 51000, N'Run M06 common/01-workload.sql before the plan-forcing demo.', 1;
GO

DECLARE @appLockResult int;
DECLARE @appLockHeld bit = 0;
DECLARE @priorQueryCaptureMode nvarchar(60);
DECLARE @expectedDemoQueryCaptureMode nvarchar(60) = N'ALL';
DECLARE @currentQueryCaptureMode nvarchar(60);
DECLARE @queryId bigint;
DECLARE @planId bigint;
DECLARE @planCount int;
DECLARE @forced bit = 0;
DECLARE @recoveryStateResolved bit = 0;

BEGIN TRY
    EXEC @appLockResult = sys.sp_getapplock
        @Resource = N'DP800.M06.QueryStoreRecovery',
        @LockMode = N'Exclusive',
        @LockOwner = N'Session',
        @LockTimeout = 60000;

    IF @appLockResult < 0
        THROW 51007, N'M06 plan-forcing demo could not acquire the Query Store recovery lock.', 1;

    SET @appLockHeld = 1;

    /* The session lock serializes both first-use DDL and recovery-state changes,
       preventing concurrent demos from adding the same column. */
    IF OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NULL
    BEGIN
        CREATE TABLE ops.M06QueryStoreRuntimeState
        (
            M06QueryStoreRuntimeStateID tinyint NOT NULL
                CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
                CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
            PriorQueryCaptureMode nvarchar(60) NOT NULL,
            ExpectedDemoQueryCaptureMode nvarchar(60) NOT NULL,
            RecoveryPhase nvarchar(30) NOT NULL
                CONSTRAINT CK_M06QueryStoreRuntimeState_RecoveryPhase
                    CHECK (RecoveryPhase IN (N'Active', N'Restored')),
            RecordedAtUtc datetime2(0) NOT NULL
        );
    END;

    IF COL_LENGTH(N'ops.M06QueryStoreRuntimeState', N'ExpectedDemoQueryCaptureMode') IS NULL
        ALTER TABLE ops.M06QueryStoreRuntimeState
            ADD ExpectedDemoQueryCaptureMode nvarchar(60) NULL;

    IF COL_LENGTH(N'ops.M06QueryStoreRuntimeState', N'RecoveryPhase') IS NULL
        ALTER TABLE ops.M06QueryStoreRuntimeState
            ADD RecoveryPhase nvarchar(30) NULL;

    SELECT @priorQueryCaptureMode = query_capture_mode_desc
    FROM sys.database_query_store_options;

    IF @priorQueryCaptureMode NOT IN (N'ALL', N'AUTO', N'CUSTOM', N'NONE')
        THROW 51003, N'Query Store did not report a supported prior QUERY_CAPTURE_MODE.', 1;

    /* This remains dynamic because a legacy table can acquire its new columns
       in this batch; static compilation would bind against its old schema. */
    EXEC sys.sp_executesql
        N'DELETE FROM ops.M06QueryStoreRuntimeState;
          INSERT ops.M06QueryStoreRuntimeState
          (
              M06QueryStoreRuntimeStateID,
              PriorQueryCaptureMode,
              ExpectedDemoQueryCaptureMode,
              RecoveryPhase,
              RecordedAtUtc
          )
          VALUES (1, @PriorQueryCaptureMode, @ExpectedDemoQueryCaptureMode, N''Active'', SYSUTCDATETIME());',
        N'@PriorQueryCaptureMode nvarchar(60), @ExpectedDemoQueryCaptureMode nvarchar(60)',
        @PriorQueryCaptureMode = @priorQueryCaptureMode,
        @ExpectedDemoQueryCaptureMode = @expectedDemoQueryCaptureMode;

    ALTER DATABASE CURRENT SET QUERY_STORE = ON
    (
        OPERATION_MODE = READ_WRITE,
        QUERY_CAPTURE_MODE = ALL,
        WAIT_STATS_CAPTURE_MODE = ON
    );

    DROP INDEX IF EXISTS IX_PerformanceOrders_CustomerDate ON ops.PerformanceOrders;
    EXEC sys.sp_recompile N'ops.PerformanceOrders';
    EXEC sys.sp_executesql N'
    SELECT COUNT_BIG(*) AS MatchingOrders
    FROM ops.PerformanceOrders
    WHERE CustomerID = 3
      AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME()) /* DP800 M06 plan forcing probe */
    OPTION (MAXDOP 1);';

    CREATE INDEX IX_PerformanceOrders_CustomerDate
    ON ops.PerformanceOrders(CustomerID, OrderDate DESC)
    INCLUDE(ProductID, Quantity, UnitPrice, OrderStatus);
    EXEC sys.sp_recompile N'ops.PerformanceOrders';
    EXEC sys.sp_executesql N'
    SELECT COUNT_BIG(*) AS MatchingOrders
    FROM ops.PerformanceOrders
    WHERE CustomerID = 3
      AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME()) /* DP800 M06 plan forcing probe */
    OPTION (MAXDOP 1);';

    SELECT TOP (1) @queryId = q.query_id
    FROM sys.query_store_query AS q
    INNER JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE qt.query_sql_text LIKE N'%DP800 M06 plan forcing probe%'
    ORDER BY q.query_id DESC;

    SELECT TOP (1) @planId = p.plan_id
    FROM sys.query_store_plan AS p
    WHERE p.query_id = @queryId
    ORDER BY p.plan_id DESC;

    SET @planCount = (SELECT COUNT(*) FROM sys.query_store_plan WHERE query_id = @queryId);

    IF @queryId IS NULL OR @planId IS NULL
        SELECT N'Query Store did not capture the plan-forcing probe; no plan was forced.' AS Result;
    ELSE IF @planCount < 2
        SELECT CONCAT(N'Query Store captured only ', @planCount,
                      N' plan for this probe. The optimizer did not produce an alternate plan, so no plan was forced.') AS Result;
    ELSE
    BEGIN
        EXEC sys.sp_query_store_force_plan @query_id = @queryId, @plan_id = @planId;
        SET @forced = 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM sys.query_store_plan
            WHERE query_id = @queryId
              AND plan_id = @planId
              AND is_forced_plan = 1
        )
            THROW 51001, N'Query Store did not mark the selected plan as forced.', 1;

        SELECT @queryId AS QueryId, @planId AS PlanId, is_forced_plan AS IsForcedPlan
        FROM sys.query_store_plan
        WHERE query_id = @queryId AND plan_id = @planId;

        EXEC sys.sp_query_store_unforce_plan @query_id = @queryId, @plan_id = @planId;
        SET @forced = 0;

        SELECT @queryId AS QueryId, @planId AS PlanId, is_forced_plan AS IsForcedPlanAfterCleanup
        FROM sys.query_store_plan
        WHERE query_id = @queryId AND plan_id = @planId;
    END;

    /* Re-read under the lifecycle lock: a mode changed outside this demo is
       user state, so discard only this stale recovery record. */
    SELECT @currentQueryCaptureMode = query_capture_mode_desc
    FROM sys.database_query_store_options;

    IF @currentQueryCaptureMode = @expectedDemoQueryCaptureMode
    BEGIN
        DECLARE @restoreAfterDemo nvarchar(max) =
            N'ALTER DATABASE CURRENT SET QUERY_STORE (QUERY_CAPTURE_MODE = ' + @priorQueryCaptureMode + N');';
        EXEC sys.sp_executesql @restoreAfterDemo;
    END;

    SET @recoveryStateResolved = 1;
    EXEC sys.sp_executesql
        N'UPDATE ops.M06QueryStoreRuntimeState
          SET RecoveryPhase = N''Restored''
          WHERE M06QueryStoreRuntimeStateID = 1
            AND RecoveryPhase = N''Active'';';

    DELETE FROM ops.M06QueryStoreRuntimeState
    WHERE M06QueryStoreRuntimeStateID = 1;

    IF @appLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M06.QueryStoreRecovery',
            @LockOwner = N'Session';
END TRY
BEGIN CATCH
    IF @forced = 1
    BEGIN
        BEGIN TRY
            EXEC sys.sp_query_store_unforce_plan @query_id = @queryId, @plan_id = @planId;
            SET @forced = 0;
        END TRY
        BEGIN CATCH
            PRINT CONCAT(N'M06 cleanup could not unforce Query Store plan ', @planId, N': ', ERROR_MESSAGE());
        END CATCH;
    END;

    IF @forced = 0 AND @recoveryStateResolved = 0
    BEGIN
        BEGIN TRY
            SELECT @currentQueryCaptureMode = query_capture_mode_desc
            FROM sys.database_query_store_options;

            IF @currentQueryCaptureMode = @expectedDemoQueryCaptureMode
            BEGIN
                DECLARE @restoreAfterError nvarchar(max) =
                    N'ALTER DATABASE CURRENT SET QUERY_STORE (QUERY_CAPTURE_MODE = ' + @priorQueryCaptureMode + N');';
                EXEC sys.sp_executesql @restoreAfterError;
            END;

            SET @recoveryStateResolved = 1;
            EXEC sys.sp_executesql
                N'UPDATE ops.M06QueryStoreRuntimeState
                  SET RecoveryPhase = N''Restored''
                  WHERE M06QueryStoreRuntimeStateID = 1
                    AND RecoveryPhase = N''Active'';';

            DELETE FROM ops.M06QueryStoreRuntimeState
            WHERE M06QueryStoreRuntimeStateID = 1;
        END TRY
        BEGIN CATCH
            PRINT CONCAT(N'M06 cleanup could not restore Query Store capture mode: ', ERROR_MESSAGE());
        END CATCH;
    END;

    IF @appLockHeld = 1
        EXEC sys.sp_releaseapplock
            @Resource = N'DP800.M06.QueryStoreRecovery',
            @LockOwner = N'Session';
    THROW;
END CATCH;
GO
