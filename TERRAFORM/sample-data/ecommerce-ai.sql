:setvar DP800_OPENAI_HOST "REPLACE_AT_RUNTIME"
:setvar DP800_EMBEDDING_DEPLOYMENT "REPLACE_AT_RUNTIME"
:setvar DP800_EMBEDDING_MODEL "REPLACE_AT_RUNTIME"
:setvar DP800_CHAT_DEPLOYMENT "REPLACE_AT_RUNTIME"

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 170;
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
ALTER DATABASE SCOPED CONFIGURATION SET ALLOW_STALE_VECTOR_INDEX = ON;
GO

DROP PROCEDURE IF EXISTS dbo.usp_AskProductQuestion;
DROP PROCEDURE IF EXISTS dbo.usp_SearchProductsHybrid;
GO

IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'dbo.ai_ProductReview'))
    DROP FULLTEXT INDEX ON dbo.ai_ProductReview;
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'DP800_AI_SearchCatalog')
    DROP FULLTEXT CATALOG DP800_AI_SearchCatalog;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ai_ProductReview') AND name = N'IX_ai_ProductReview_ReviewVector')
    DROP INDEX IX_ai_ProductReview_ReviewVector ON dbo.ai_ProductReview;
GO

DROP TABLE IF EXISTS dbo.ai_ProductReview;
DROP TABLE IF EXISTS dbo.ai_Product;
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'DP800_EmbeddingModel')
    DROP EXTERNAL MODEL DP800_EmbeddingModel;
GO

IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = N'https://$(DP800_OPENAI_HOST)')
    DROP DATABASE SCOPED CREDENTIAL [https://$(DP800_OPENAI_HOST)];
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY;
GO

CREATE DATABASE SCOPED CREDENTIAL [https://$(DP800_OPENAI_HOST)]
WITH IDENTITY = 'Managed Identity',
    SECRET = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO

CREATE EXTERNAL MODEL DP800_EmbeddingModel
WITH
(
    LOCATION = 'https://$(DP800_OPENAI_HOST)/openai/deployments/$(DP800_EMBEDDING_DEPLOYMENT)/embeddings?api-version=2024-10-21',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = '$(DP800_EMBEDDING_MODEL)',
    CREDENTIAL = [https://$(DP800_OPENAI_HOST)]
);
GO

CREATE TABLE dbo.ai_Product
(
    ProductID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ai_Product PRIMARY KEY,
    ProductName nvarchar(120) NOT NULL,
    Category nvarchar(60) NOT NULL,
    UnitPrice decimal(10,2) NOT NULL,
    ProductDescription nvarchar(1000) NOT NULL
);

CREATE TABLE dbo.ai_ProductReview
(
    ReviewID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ai_ProductReview PRIMARY KEY,
    ProductID int NOT NULL CONSTRAINT FK_ai_ProductReview_Product REFERENCES dbo.ai_Product(ProductID),
    ReviewTitle nvarchar(200) NOT NULL,
    ReviewText nvarchar(max) NOT NULL,
    Rating tinyint NOT NULL CONSTRAINT CK_ai_ProductReview_Rating CHECK (Rating BETWEEN 1 AND 5),
    ReviewVector vector(1536) NULL
);
GO

INSERT dbo.ai_Product (ProductName, Category, UnitPrice, ProductDescription)
VALUES
    (N'Kumo Trail 29', N'Bikes', 1499.00, N'An aluminum trail bike tuned for technical rocky climbs and controlled descents.'),
    (N'Sakura Puncture Guard', N'Components', 64.50, N'A durable 29-inch tire with reinforced protection for gravel and road debris.'),
    (N'Yoru Beacon 800', N'Accessories', 46.00, N'An 800-lumen rechargeable light with weather sealing for dark rainy commutes.'),
    (N'Fuyu Grip Gloves', N'Clothing', 39.00, N'Insulated winter cycling gloves designed to preserve brake control.'),
    (N'Harbor Comfort Saddle', N'Components', 82.00, N'A pressure-relief saddle for long-distance touring and weekend family rides.'),
    (N'Mizu Commuter Shell', N'Clothing', 118.00, N'A breathable waterproof cycling jacket with reflective panels.');

INSERT dbo.ai_ProductReview (ProductID, ReviewTitle, ReviewText, Rating)
VALUES
    (1, N'Confident on technical trails', N'Stable handling over rocky climbs and precise control on steep descents.', 5),
    (1, N'Balanced weekend bike', N'Comfortable enough for a family ride but still capable on rough forest trails.', 4),
    (2, N'No flats on gravel', N'The reinforced tire resisted punctures during long rides on rough gravel roads.', 5),
    (2, N'Durable commuter tire', N'Good tread life and dependable protection from glass and road debris.', 4),
    (3, N'Visible in heavy rain', N'The bright beam and reliable sealing made dark wet commutes feel much safer.', 5),
    (4, N'Warm without bulk', N'My hands stayed warm below freezing while I could still operate the brake levers.', 5),
    (5, N'Comfort after four hours', N'The pressure-relief shape reduced soreness during a long touring ride.', 4),
    (6, N'Dry and easy to see', N'The shell blocked steady rain and the reflective panels stood out at night.', 5);

INSERT dbo.ai_ProductReview (ProductID, ReviewTitle, ReviewText, Rating)
SELECT
    reviews.ProductID,
    CONCAT(reviews.ReviewTitle, N' - sample ', variants.VariantNumber),
    CONCAT(reviews.ReviewText, N' Training sample variant ', variants.VariantNumber, N'.'),
    reviews.Rating
FROM dbo.ai_ProductReview AS reviews
CROSS JOIN
(
    VALUES (1), (2), (3), (4), (5), (6),
           (7), (8), (9), (10), (11), (12)
) AS variants(VariantNumber);
GO

DECLARE @BatchSize int = 4;
DECLARE @RowsUpdated int = 1;
DECLARE @RetryCount int;
DECLARE @BatchCount int = 0;
DECLARE @MaxBatchCount int = 30;

WHILE @RowsUpdated > 0 AND @BatchCount < @MaxBatchCount
BEGIN
    SET @BatchCount += 1;
    SET @RetryCount = 0;

    RETRY_EMBEDDINGS:
    BEGIN TRY
        UPDATE TOP (@BatchSize) reviews
        SET ReviewVector = AI_GENERATE_EMBEDDINGS
        (
            products.ProductName + N' - ' + reviews.ReviewTitle + N': ' + reviews.ReviewText
            USE MODEL DP800_EmbeddingModel
        )
        FROM dbo.ai_ProductReview AS reviews
        INNER JOIN dbo.ai_Product AS products ON products.ProductID = reviews.ProductID
        WHERE reviews.ReviewVector IS NULL;

        SET @RowsUpdated = @@ROWCOUNT;
        IF @RowsUpdated > 0
            WAITFOR DELAY '00:00:02';
    END TRY
    BEGIN CATCH
        SET @RetryCount += 1;
        IF @RetryCount <= 3
        BEGIN
            WAITFOR DELAY '00:00:05';
            GOTO RETRY_EMBEDDINGS;
        END;
        THROW;
    END CATCH;
END;

IF EXISTS (SELECT 1 FROM dbo.ai_ProductReview WHERE ReviewVector IS NULL)
    THROW 51101, 'Embedding generation did not complete within the batch limit.', 1;
GO

CREATE VECTOR INDEX IX_ai_ProductReview_ReviewVector
ON dbo.ai_ProductReview(ReviewVector)
WITH (METRIC = 'cosine', TYPE = 'DISKANN');
GO

CREATE FULLTEXT CATALOG DP800_AI_SearchCatalog AS DEFAULT;
GO

CREATE FULLTEXT INDEX ON dbo.ai_ProductReview
(
    ReviewTitle LANGUAGE 1033,
    ReviewText LANGUAGE 1033
)
KEY INDEX PK_ai_ProductReview
ON DP800_AI_SearchCatalog
WITH (CHANGE_TRACKING AUTO);
GO

DECLARE @FullTextDeadline datetime2(0) = DATEADD(second, 120, SYSUTCDATETIME());
WHILE FULLTEXTCATALOGPROPERTY(N'DP800_AI_SearchCatalog', N'PopulateStatus') <> 0
BEGIN
    IF SYSUTCDATETIME() >= @FullTextDeadline
        THROW 51102, 'Full-text population timed out after 120 seconds.', 1;
    WAITFOR DELAY '00:00:01';
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SearchProductsHybrid
    @SearchText nvarchar(1000),
    @TopN int = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SearchVector vector(1536);
    DECLARE @CandidateCount int = CASE WHEN @TopN < 50 THEN 50 ELSE @TopN END;
    DECLARE @RrfK int = 60;

    SELECT @SearchVector = AI_GENERATE_EMBEDDINGS(@SearchText USE MODEL DP800_EmbeddingModel);

    WITH keyword_search AS
    (
        SELECT TOP (@CandidateCount)
            reviews.ReviewID,
            RANK() OVER (ORDER BY fulltext_result.[RANK] DESC) AS keyword_rank
        FROM dbo.ai_ProductReview AS reviews
        INNER JOIN FREETEXTTABLE
        (
            dbo.ai_ProductReview,
            (ReviewTitle, ReviewText),
            @SearchText
        ) AS fulltext_result ON reviews.ReviewID = fulltext_result.[KEY]
        ORDER BY fulltext_result.[RANK] DESC
    ),
    vector_search AS
    (
        SELECT
            ReviewID,
            RANK() OVER (ORDER BY distance) AS vector_rank
        FROM
        (
            SELECT TOP (@CandidateCount) WITH APPROXIMATE
                reviews.ReviewID,
                nearest.distance
            FROM VECTOR_SEARCH
            (
                TABLE = dbo.ai_ProductReview AS reviews,
                COLUMN = ReviewVector,
                SIMILAR_TO = @SearchVector,
                METRIC = 'cosine'
            ) AS nearest
            ORDER BY nearest.distance
        ) AS candidates
    ),
    combined AS
    (
        SELECT
            COALESCE(keywords.ReviewID, vectors.ReviewID) AS ReviewID,
            keywords.keyword_rank,
            vectors.vector_rank,
            COALESCE(1.0 / (@RrfK + keywords.keyword_rank), 0.0) +
            COALESCE(1.0 / (@RrfK + vectors.vector_rank), 0.0) AS rrf_score
        FROM keyword_search AS keywords
        FULL OUTER JOIN vector_search AS vectors ON vectors.ReviewID = keywords.ReviewID
    )
    SELECT TOP (@TopN)
        products.ProductName,
        products.Category,
        products.UnitPrice,
        reviews.Rating,
        reviews.ReviewTitle,
        reviews.ReviewText,
        combined.keyword_rank,
        combined.vector_rank,
        combined.rrf_score
    FROM combined
    INNER JOIN dbo.ai_ProductReview AS reviews ON reviews.ReviewID = combined.ReviewID
    INNER JOIN dbo.ai_Product AS products ON products.ProductID = reviews.ProductID
    ORDER BY combined.rrf_score DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AskProductQuestion
    @Question nvarchar(1000),
    @Answer nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @QuestionVector vector(1536);
    DECLARE @Context nvarchar(max);
    DECLARE @Payload nvarchar(max);
    DECLARE @Response nvarchar(max);
    DECLARE @ReturnValue int;

    SELECT @QuestionVector = AI_GENERATE_EMBEDDINGS(@Question USE MODEL DP800_EmbeddingModel);

    SET @Context =
    (
        SELECT TOP (5) WITH APPROXIMATE
            products.ProductName,
            products.Category,
            products.UnitPrice,
            reviews.Rating,
            reviews.ReviewTitle,
            reviews.ReviewText
        FROM VECTOR_SEARCH
        (
            TABLE = dbo.ai_ProductReview AS reviews,
            COLUMN = ReviewVector,
            SIMILAR_TO = @QuestionVector,
            METRIC = 'cosine'
        ) AS nearest
        INNER JOIN dbo.ai_Product AS products ON products.ProductID = reviews.ProductID
        ORDER BY nearest.distance
        FOR JSON PATH
    );

    SET @Payload = JSON_OBJECT
    (
        'messages': JSON_ARRAY
        (
            JSON_OBJECT
            (
                'role': 'developer',
                'content': 'Answer only from the supplied fictional ecommerce context. Cite product names and ratings. Say when evidence is insufficient.'
            ),
            JSON_OBJECT
            (
                'role': 'user',
                'content': CONCAT(N'Product context: ', COALESCE(@Context, N'[]'), CHAR(10), N'Question: ', @Question)
            )
        ),
        'max_completion_tokens': 700,
        'reasoning_effort': 'low'
    );

    EXECUTE @ReturnValue = sys.sp_invoke_external_rest_endpoint
        @url = N'https://$(DP800_OPENAI_HOST)/openai/deployments/$(DP800_CHAT_DEPLOYMENT)/chat/completions?api-version=2024-10-21',
        @method = N'POST',
        @credential = [https://$(DP800_OPENAI_HOST)],
        @payload = @Payload,
        @response = @Response OUTPUT;

    IF @ReturnValue <> 0
    BEGIN
        DECLARE @ErrorMessage nvarchar(2048) = CONCAT
        (
            N'Azure OpenAI chat invocation failed with HTTP status ',
            @ReturnValue,
            N': ',
            COALESCE(JSON_VALUE(@Response, '$.response.status.http.description'), N'No response description.')
        );
        THROW 51110, @ErrorMessage, 1;
    END;

    SET @Answer = JSON_VALUE(@Response, '$.result.choices[0].message.content');
    IF NULLIF(@Answer, N'') IS NULL
        THROW 51111, 'Azure OpenAI returned an empty RAG answer.', 1;
END;
GO

IF EXISTS (SELECT 1 FROM dbo.ai_ProductReview WHERE ReviewVector IS NULL)
    THROW 51120, 'Embedding smoke test failed: one or more review vectors are null.', 1;

DECLARE @ExactQuery vector(1536);
SELECT @ExactQuery = AI_GENERATE_EMBEDDINGS
(
    N'puncture resistant tire for rough gravel'
    USE MODEL DP800_EmbeddingModel
);

SELECT TOP (3)
    products.ProductName,
    VECTOR_DISTANCE('cosine', @ExactQuery, reviews.ReviewVector) AS Distance
FROM dbo.ai_ProductReview AS reviews
INNER JOIN dbo.ai_Product AS products ON products.ProductID = reviews.ProductID
ORDER BY Distance;

EXEC dbo.usp_SearchProductsHybrid
    @SearchText = N'durable puncture resistant tire for rough roads',
    @TopN = 3;

DECLARE @SmokeAnswer nvarchar(max);
EXEC dbo.usp_AskProductQuestion
    @Question = N'Which product helps prevent punctures on rough gravel?',
    @Answer = @SmokeAnswer OUTPUT;

SELECT @SmokeAnswer AS RagSmokeTestAnswer;
GO
