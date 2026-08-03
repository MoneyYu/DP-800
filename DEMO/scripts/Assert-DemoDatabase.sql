/*
    Assert-DemoDatabase.sql

    Read-only safety guard for the unified AdventureGearAI demo. It performs NO
    writes and only inspects the current connection and the operational marker.

    The guard FAILS (RAISERROR severity 16, which aborts sqlcmd when invoked with
    -b) unless every one of the following is true:
        * The active connection is on a database literally named AdventureGearAI.
        * The ops.DemoEnvironment singleton marker table exists.
        * A valid marker row (DemoEnvironmentID = 1, DatabaseName = AdventureGearAI)
          is present.

    Any tooling that runs demo module setup against a non-master database should
    execute this guard first so a mis-targeted connection can never mutate the
    wrong database. The messages are explicit so operators can diagnose quickly.
*/
SET NOCOUNT ON;

DECLARE @currentDatabase sysname = DB_NAME();

IF @currentDatabase <> N'AdventureGearAI'
BEGIN
    RAISERROR(
        N'Demo database guard failed: connected to database "%s" but the unified demo only permits AdventureGearAI. Re-run against the AdventureGearAI database.',
        16, 1, @currentDatabase);
    RETURN;
END;

IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
BEGIN
    RAISERROR(
        N'Demo database guard failed: AdventureGearAI is missing the ops.DemoEnvironment marker table. Run the core bootstrap (DEMO/bootstrap/Invoke-Bootstrap.ps1) before executing demo modules.',
        16, 1);
    RETURN;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM ops.DemoEnvironment
    WHERE DemoEnvironmentID = 1
      AND DatabaseName = N'AdventureGearAI'
)
BEGIN
    RAISERROR(
        N'Demo database guard failed: ops.DemoEnvironment does not contain a valid AdventureGearAI marker row. Re-run the core bootstrap to initialize the marker before executing demo modules.',
        16, 1);
    RETURN;
END;

PRINT N'Demo database guard passed: connected to AdventureGearAI with a valid ops.DemoEnvironment marker.';
