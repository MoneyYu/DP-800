SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF NOT EXISTS (SELECT 1 FROM sys.types WHERE name = N'vector')
BEGIN
    SELECT N'ANN setup skipped' AS Result, N'The vector data type is unavailable in this target database.' AS Reason;
    RETURN;
END;
BEGIN TRY
    EXEC sys.sp_executesql N'ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 102
        SELECT N'PREVIEW_FEATURES was not enabled' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;

BEGIN TRY
    EXEC sys.sp_executesql N'ALTER DATABASE SCOPED CONFIGURATION SET ALLOW_STALE_VECTOR_INDEX = ON;';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 102
        SELECT N'ALLOW_STALE_VECTOR_INDEX was not enabled' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;

BEGIN TRY
    EXEC sys.sp_executesql N'
        IF COL_LENGTH(N''search.SearchDocuments'', N''SearchVector'') IS NULL
            ALTER TABLE search.SearchDocuments ADD SearchVector vector(3) NULL;

        UPDATE search.SearchDocuments
        SET SearchVector =
            CASE
                WHEN ProductName LIKE N''%Tire%'' THEN CAST(''[1,0,0]'' AS vector(3))
                WHEN ProductName LIKE N''%Light%'' THEN CAST(''[0,1,0]'' AS vector(3))
                ELSE CAST(''[0,0,1]'' AS vector(3))
            END;

        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N''search.SearchDocuments'') AND name = N''IX_AdventureGear_SearchVector'')
            CREATE VECTOR INDEX IX_AdventureGear_SearchVector
            ON search.SearchDocuments(SearchVector)
            WITH (METRIC = ''cosine'', TYPE = ''DISKANN'');

        DECLARE @QueryVector vector(3) = CAST(''[1,0,0]'' AS vector(3));
        SELECT TOP (3) WITH APPROXIMATE
            ProductName,
            DocumentText,
            VECTOR_DISTANCE(''cosine'', @QueryVector, SearchVector) AS VectorDistance
        FROM search.SearchDocuments
        ORDER BY VectorDistance;';
    SELECT N'ANN vector index and approximate search executed.' AS Result;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (102, 195, 1919, 2715)
        SELECT N'ANN setup skipped' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;
GO
