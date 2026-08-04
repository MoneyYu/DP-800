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

DECLARE @priorQueryCaptureMode nvarchar(60) =
(
    SELECT query_capture_mode_desc
    FROM sys.database_query_store_options
);
DECLARE @expectedDemoQueryCaptureMode nvarchar(60) = N'ALL';
IF @priorQueryCaptureMode NOT IN (N'ALL', N'AUTO', N'CUSTOM', N'NONE')
    THROW 51003, N'Query Store did not report a supported prior QUERY_CAPTURE_MODE.', 1;

DELETE FROM ops.M06QueryStoreRuntimeState;
INSERT ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID,
    PriorQueryCaptureMode,
    ExpectedDemoQueryCaptureMode,
    RecoveryPhase,
    RecordedAtUtc
)
VALUES (1, @priorQueryCaptureMode, @expectedDemoQueryCaptureMode, N'Active', SYSUTCDATETIME());

ALTER DATABASE CURRENT SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,
    WAIT_STATS_CAPTURE_MODE = ON
);

DECLARE @queryId bigint;
DECLARE @planId bigint;
DECLARE @planCount int;
DECLARE @forced bit = 0;
DECLARE @captureModeRestored bit = 0;

BEGIN TRY
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

    IF @forced = 0
    BEGIN
        BEGIN TRY
            DECLARE @restoreAfterError nvarchar(max) =
                N'ALTER DATABASE CURRENT SET QUERY_STORE (QUERY_CAPTURE_MODE = ' + @priorQueryCaptureMode + N');';
            EXEC sys.sp_executesql @restoreAfterError;
            SET @captureModeRestored = 1;

            UPDATE ops.M06QueryStoreRuntimeState
            SET RecoveryPhase = N'Restored'
            WHERE M06QueryStoreRuntimeStateID = 1
              AND RecoveryPhase = N'Active';

            DELETE FROM ops.M06QueryStoreRuntimeState
            WHERE M06QueryStoreRuntimeStateID = 1;
        END TRY
        BEGIN CATCH
            PRINT CONCAT(N'M06 cleanup could not restore Query Store capture mode: ', ERROR_MESSAGE());
        END CATCH;
    END;

    THROW;
END CATCH;

DECLARE @restoreAfterDemo nvarchar(max) =
    N'ALTER DATABASE CURRENT SET QUERY_STORE (QUERY_CAPTURE_MODE = ' + @priorQueryCaptureMode + N');';
EXEC sys.sp_executesql @restoreAfterDemo;
SET @captureModeRestored = 1;

IF @forced = 0 AND @captureModeRestored = 1
BEGIN
    UPDATE ops.M06QueryStoreRuntimeState
    SET RecoveryPhase = N'Restored'
    WHERE M06QueryStoreRuntimeStateID = 1
      AND RecoveryPhase = N'Active';

    DELETE FROM ops.M06QueryStoreRuntimeState
    WHERE M06QueryStoreRuntimeStateID = 1;
END;
GO
