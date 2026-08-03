SET NOCOUNT ON;

SELECT
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('EngineEdition') AS EngineEdition;

DECLARE @VectorSupported bit = 0;
BEGIN TRY
    EXEC sys.sp_executesql N'
        DROP TABLE IF EXISTS dbo.VectorFeatureProbe;
        CREATE TABLE dbo.VectorFeatureProbe
        (
            ProbeID int NOT NULL PRIMARY KEY,
            Embedding vector(3) NULL
        );
        INSERT dbo.VectorFeatureProbe (ProbeID, Embedding)
        VALUES (1, CAST(''[1,0,0]'' AS vector(3)));
        SELECT ProbeID, VECTORPROPERTY(Embedding, ''Dimensions'') AS Dimensions
        FROM dbo.VectorFeatureProbe;
        DROP TABLE dbo.VectorFeatureProbe;';
    SET @VectorSupported = 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (102, 195, 2715)
        SELECT N'Vector demo skipped' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;

IF @VectorSupported = 1
    SELECT N'Vector data type and basic vector functions executed successfully.' AS Result;

BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (0) * FROM sys.external_models;';
    SELECT N'External model catalog exists, but model creation and AI_GENERATE_EMBEDDINGS are skipped locally because no approved endpoint/credential was supplied.' AS Result;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 208
        SELECT N'External model demo skipped' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;
GO
