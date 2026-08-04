/*
    M10 local search — full-text, exact vector, and hybrid RRF for AdventureGearAI.

    Runs against search.SearchDocuments (seeded by common/01-search-data.sql).
    Full-text and vector support are detected independently and the actual skip
    reason is emitted for anything the installed build does not support. The local
    path performs EXACT vector search (VECTOR_DISTANCE over all rows); the DiskANN
    approximate index lives in azure/01-ann-search.sql because preview/GA behavior
    differs from local SQL Server 2025 containers.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @FullTextInstalled bit = CONVERT(bit, FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'));
DECLARE @FullTextReady bit = 0;
DECLARE @VectorReady bit = 0;

IF @FullTextInstalled = 1
BEGIN
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N''AdventureGearSearchCatalog'')
            CREATE FULLTEXT CATALOG AdventureGearSearchCatalog AS DEFAULT;
        IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N''search.SearchDocuments''))
            CREATE FULLTEXT INDEX ON search.SearchDocuments
            (
                ProductName LANGUAGE 1033,
                DocumentText LANGUAGE 1033
            )
            KEY INDEX PK_SearchDocuments
            ON AdventureGearSearchCatalog
            WITH (CHANGE_TRACKING AUTO);';
    SET @FullTextReady = 1;
END
ELSE
    SELECT N'Full-text search skipped' AS Result, N'Full-Text Search is not installed in this SQL Server image.' AS Reason;

IF @FullTextReady = 1
BEGIN
    WHILE FULLTEXTCATALOGPROPERTY(N'AdventureGearSearchCatalog', N'PopulateStatus') <> 0
        WAITFOR DELAY '00:00:01';

    EXEC sys.sp_executesql N'
        SELECT TOP (10)
            d.ProductName,
            d.DocumentText,
            keywordResult.[RANK] AS FullTextRank
        FROM CONTAINSTABLE(search.SearchDocuments, (ProductName, DocumentText),
            ''FORMSOF(INFLECTIONAL, ride) OR "puncture*"'') AS keywordResult
        INNER JOIN search.SearchDocuments AS d ON d.DocumentID = keywordResult.[KEY]
        ORDER BY keywordResult.[RANK] DESC;';
END;

BEGIN TRY
    EXEC sys.sp_executesql N'
        DECLARE @QueryVector vector(3) = CAST(''[1,0,0]'' AS vector(3));
        SELECT TOP (5)
            ProductName,
            DocumentText,
            VECTOR_DISTANCE(''cosine'', @QueryVector, SearchVector) AS VectorDistance
        FROM search.SearchDocuments
        ORDER BY VectorDistance;';
    SET @VectorReady = 1;
    SELECT N'Exact vector search supported and executed.' AS Result;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (102, 195, 2715)
        SELECT N'Vector search skipped' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;

IF @FullTextReady = 1 AND @VectorReady = 1
BEGIN
    EXEC sys.sp_executesql N'
        DECLARE @QueryVector vector(3) = CAST(''[1,0,0]'' AS vector(3));
        WITH KeywordResults AS
        (
            SELECT d.DocumentID,
                   RANK() OVER (ORDER BY ft.[RANK] DESC) AS KeywordRank
            FROM CONTAINSTABLE(search.SearchDocuments, (ProductName, DocumentText), ''tire OR puncture'') AS ft
            INNER JOIN search.SearchDocuments AS d ON d.DocumentID = ft.[KEY]
        ),
        VectorResults AS
        (
            SELECT DocumentID,
                   RANK() OVER (ORDER BY VECTOR_DISTANCE(''cosine'', @QueryVector, SearchVector)) AS VectorRank
            FROM search.SearchDocuments
        )
        SELECT TOP (5)
            d.ProductName,
            d.DocumentText,
            COALESCE(1.0 / (60 + k.KeywordRank), 0) + COALESCE(1.0 / (60 + v.VectorRank), 0) AS RrfScore
        FROM KeywordResults AS k
        FULL OUTER JOIN VectorResults AS v ON v.DocumentID = k.DocumentID
        INNER JOIN search.SearchDocuments AS d ON d.DocumentID = COALESCE(k.DocumentID, v.DocumentID)
        ORDER BY RrfScore DESC;';
END
ELSE
    SELECT N'Hybrid search skipped' AS Result,
           N'Hybrid search requires both successful full-text and vector feature detection.' AS Reason;
GO
