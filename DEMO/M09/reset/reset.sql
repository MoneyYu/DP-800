/*
    M09 reset/reset.sql

    Module-scoped reset for the unified AdventureGearAI demo. It NEVER drops a
    database. It removes ONLY the Module 9 embedding objects and returns Module 9
    to a NotStarted baseline. The canonical catalog/customer core the documents
    are built from is left intact.

    Module-owned objects removed (dependency-safe order):
      * AdventureGearEmbeddingModel  (Azure external model, feature/edition gated)
      * ai.VectorFeatureProbe        (transient local feature-detection probe)
      * ai.EmbeddingDocuments        (embedding source-document table)

    Dependency/staleness reset: M10 (vector search) and M11 (RAG) consume the M09
    embedding pipeline, so resetting M09 marks M10 and M11 stale (NotStarted) as
    well, clearing their timestamps and errors.

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
    RAISERROR(N'M09 reset guard failed: connected to "%s" but only AdventureGearAI may be reset.', 16, 1, @db);
    SET NOEXEC ON;
END;
GO

/* Guard 2: refuse to run without a valid AdventureGearAI environment marker. */
IF OBJECT_ID(N'ops.DemoEnvironment', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1 AND DatabaseName = N'AdventureGearAI')
BEGIN
    RAISERROR(N'M09 reset guard failed: AdventureGearAI ops.DemoEnvironment marker is missing or invalid.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------------------------------------------------------------------
   Teardown the Azure external model when the build exposes external models and
   one exists. Feature/edition gated, so failures for unsupported engines are
   swallowed (the azure-only model is never provisioned locally). The referenced
   managed-identity credential is created out of band and is never touched here.
--------------------------------------------------------------------------- */
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'AdventureGearEmbeddingModel')
        EXEC sys.sp_executesql N'DROP EXTERNAL MODEL AdventureGearEmbeddingModel;';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (208, 102, 195)
        PRINT N'M09 reset: external model teardown skipped (external models not supported or none present).';
    ELSE
        THROW;
END CATCH;
GO

/* ---------------------------------------------------------------------------
   Teardown module-owned tables (probe -> embedding documents). The canonical
   catalog/customer core is never dropped.
--------------------------------------------------------------------------- */
DROP TABLE IF EXISTS ai.VectorFeatureProbe;
DROP TABLE IF EXISTS ai.EmbeddingDocuments;
GO

/* ---------------------------------------------------------------------------
   State reset: Module 9 plus its downstream dependents M10 and M11 (stale).
--------------------------------------------------------------------------- */
UPDATE ops.DemoModuleState
SET Status = N'NotStarted',
    StartedAtUtc = NULL,
    CompletedAtUtc = NULL,
    LastError = NULL,
    ErrorNumber = NULL,
    ErrorLine = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE ModuleNumber IN (9, 10, 11);
GO

SET NOEXEC OFF;
GO
PRINT N'M09 reset complete: embedding objects removed; M09/M10/M11 marked NotStarted.';
GO
