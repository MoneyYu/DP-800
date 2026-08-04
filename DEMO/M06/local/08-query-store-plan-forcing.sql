/*
    M06 local/08-query-store-plan-forcing.sql (INTERACTIVE — excluded from runner)

    Captures an unindexed and indexed version of one stable query, then forces
    one captured plan only when Query Store has two or more plans. The script
    always unforces the plan it forced. If the optimizer retains one plan, it
    reports that fact instead of claiming forcing succeeded.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.PerformanceOrders', N'U') IS NULL
    THROW 51000, N'Run M06 common/01-workload.sql before the plan-forcing demo.', 1;
GO

ALTER DATABASE CURRENT SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,
    WAIT_STATS_CAPTURE_MODE = ON
);
GO

DROP INDEX IF EXISTS IX_PerformanceOrders_CustomerDate ON ops.PerformanceOrders;
EXEC sys.sp_recompile N'ops.PerformanceOrders';
EXEC sys.sp_executesql N'
SELECT COUNT_BIG(*) AS MatchingOrders
FROM ops.PerformanceOrders
WHERE CustomerID = 3
  AND OrderDate >= DATEADD(day, -30, SYSUTCDATETIME()) /* DP800 M06 plan forcing probe */
OPTION (MAXDOP 1);';
GO

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
GO

DECLARE @queryId bigint =
(
    SELECT TOP (1) q.query_id
    FROM sys.query_store_query AS q
    INNER JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE qt.query_sql_text LIKE N'%DP800 M06 plan forcing probe%'
    ORDER BY q.query_id DESC
);
DECLARE @planId bigint =
(
    SELECT TOP (1) p.plan_id
    FROM sys.query_store_plan AS p
    WHERE p.query_id = @queryId
    ORDER BY p.plan_id DESC
);
DECLARE @planCount int = (SELECT COUNT(*) FROM sys.query_store_plan WHERE query_id = @queryId);

IF @queryId IS NULL OR @planId IS NULL
BEGIN
    SELECT N'Query Store did not capture the plan-forcing probe; no plan was forced.' AS Result;
    RETURN;
END;

IF @planCount < 2
BEGIN
    SELECT CONCAT(N'Query Store captured only ', @planCount,
                  N' plan for this probe. The optimizer did not produce an alternate plan, so no plan was forced.') AS Result;
    RETURN;
END;

DECLARE @forced bit = 0;
BEGIN TRY
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
END TRY
BEGIN CATCH
    SELECT CONCAT(N'Query Store plan forcing did not succeed: ', ERROR_MESSAGE()) AS Result;
END CATCH;

IF @forced = 1
BEGIN
    EXEC sys.sp_query_store_unforce_plan @query_id = @queryId, @plan_id = @planId;
    SELECT @queryId AS QueryId, @planId AS PlanId, is_forced_plan AS IsForcedPlanAfterCleanup
    FROM sys.query_store_plan
    WHERE query_id = @queryId AND plan_id = @planId;
END;
GO
