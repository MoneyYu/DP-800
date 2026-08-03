SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @FullTextInstalled bit = CONVERT(bit, FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'));
DECLARE @FullTextReady bit = 0;
DECLARE @VectorReady bit = 0;
DECLARE @AnnReady bit = 0;

IF @FullTextInstalled = 1
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql N'
            IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N''DP800_SearchCatalog'')
                CREATE FULLTEXT CATALOG DP800_SearchCatalog AS DEFAULT;
            IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N''dbo.SearchDocuments''))
                CREATE FULLTEXT INDEX ON dbo.SearchDocuments
                (
                    ProductName LANGUAGE 1033,
                    DocumentText LANGUAGE 1033
                )
                KEY INDEX PK_SearchDocuments
                ON DP800_SearchCatalog
                WITH (CHANGE_TRACKING AUTO);';
        SET @FullTextReady = 1;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END
ELSE
    SELECT N'Full-text search skipped' AS Result, N'Full-Text Search is not installed in this SQL Server image.' AS Reason;

IF @FullTextReady = 1
BEGIN
    WHILE FULLTEXTCATALOGPROPERTY(N'DP800_SearchCatalog', N'PopulateStatus') <> 0
        WAITFOR DELAY '00:00:01';

    EXEC sys.sp_executesql N'
        SELECT TOP (10)
            d.ProductName,
            d.DocumentText,
            keywordResult.[RANK] AS FullTextRank
        FROM CONTAINSTABLE(dbo.SearchDocuments, (ProductName, DocumentText),
            ''FORMSOF(INFLECTIONAL, ride) OR "puncture*"'') AS keywordResult
        INNER JOIN dbo.SearchDocuments AS d ON d.DocumentID = keywordResult.[KEY]
        ORDER BY keywordResult.[RANK] DESC;';
END;

BEGIN TRY
    EXEC sys.sp_executesql N'
        IF COL_LENGTH(N''dbo.SearchDocuments'', N''SearchVector'') IS NULL
            ALTER TABLE dbo.SearchDocuments ADD SearchVector vector(3) NULL;';

    EXEC sys.sp_executesql N'
        UPDATE dbo.SearchDocuments
        SET SearchVector =
            CASE
                WHEN ProductName LIKE N''%Tire%'' THEN CAST(''[1,0,0]'' AS vector(3))
                WHEN ProductName LIKE N''%Light%'' THEN CAST(''[0,1,0]'' AS vector(3))
                ELSE CAST(''[0,0,1]'' AS vector(3))
            END;
        DECLARE @QueryVector vector(3) = CAST(''[1,0,0]'' AS vector(3));
        SELECT TOP (5)
            ProductName,
            DocumentText,
            VECTOR_DISTANCE(''cosine'', @QueryVector, SearchVector) AS VectorDistance
        FROM dbo.SearchDocuments
        ORDER BY VectorDistance;';
    SET @VectorReady = 1;
    SELECT N'Vector search supported and executed.' AS Result;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (102, 195, 2715)
        SELECT N'Vector search skipped' AS Result, ERROR_MESSAGE() AS Reason;
    ELSE
        THROW;
END CATCH;

IF @VectorReady = 1
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql N'ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;';
        EXEC sys.sp_executesql N'ALTER DATABASE SCOPED CONFIGURATION SET ALLOW_STALE_VECTOR_INDEX = ON;';
        EXEC sys.sp_executesql N'
            IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N''dbo.SearchDocuments'') AND name = N''IX_DP800_SearchVector'')
                CREATE VECTOR INDEX IX_DP800_SearchVector
                ON dbo.SearchDocuments(SearchVector)
                WITH (METRIC = ''cosine'', TYPE = ''DISKANN'');';
        EXEC sys.sp_executesql N'
            DECLARE @QueryVector vector(3) = CAST(''[1,0,0]'' AS vector(3));
            SELECT ProductName, distance
            FROM VECTOR_SEARCH(
                TABLE = dbo.SearchDocuments AS documents,
                COLUMN = SearchVector,
                SIMILAR_TO = @QueryVector,
                METRIC = ''cosine'',
                TOP_N = 3
            ) AS nearest;';
        SET @AnnReady = 1;
        SELECT N'ANN VECTOR_SEARCH supported and executed.' AS Result;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (102, 195, 1919, 2715)
            SELECT N'ANN VECTOR_SEARCH skipped' AS Result, ERROR_MESSAGE() AS Reason;
        ELSE
            THROW;
    END CATCH;
END;

IF @FullTextReady = 1 AND @VectorReady = 1
BEGIN
    EXEC sys.sp_executesql N'
        DECLARE @QueryVector vector(3) = CAST(''[1,0,0]'' AS vector(3));
        WITH KeywordResults AS
        (
            SELECT d.DocumentID,
                   RANK() OVER (ORDER BY ft.[RANK] DESC) AS KeywordRank
            FROM CONTAINSTABLE(dbo.SearchDocuments, (ProductName, DocumentText), ''tire OR puncture'') AS ft
            INNER JOIN dbo.SearchDocuments AS d ON d.DocumentID = ft.[KEY]
        ),
        VectorResults AS
        (
            SELECT DocumentID,
                   RANK() OVER (ORDER BY VECTOR_DISTANCE(''cosine'', @QueryVector, SearchVector)) AS VectorRank
            FROM dbo.SearchDocuments
        )
        SELECT TOP (5)
            d.ProductName,
            d.DocumentText,
            COALESCE(1.0 / (60 + k.KeywordRank), 0) + COALESCE(1.0 / (60 + v.VectorRank), 0) AS RrfScore
        FROM KeywordResults AS k
        FULL OUTER JOIN VectorResults AS v ON v.DocumentID = k.DocumentID
        INNER JOIN dbo.SearchDocuments AS d ON d.DocumentID = COALESCE(k.DocumentID, v.DocumentID)
        ORDER BY RrfScore DESC;';
END
ELSE
    SELECT N'Hybrid search skipped' AS Result,
           N'Hybrid search requires both successful full-text and vector feature detection.' AS Reason;
GO
