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
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Guard 1: refuse to run against anything but AdventureGearAI. */
IF DB_NAME() <> N'AdventureGearAI'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'M11 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
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
--------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS ai.usp_AskProductQuestion;
DROP PROCEDURE IF EXISTS ai.usp_BuildRagPrompt;
GO

/* ---------------------------------------------------------------------------
   State reset: only Module 11 (leaf; no dependents).
--------------------------------------------------------------------------- */
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
