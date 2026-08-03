SET NOCOUNT ON;
GO

DROP PROCEDURE IF EXISTS dbo.usp_BuildRagPrompt;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BuildRagPrompt
    @Question nvarchar(1000)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SearchTerm nvarchar(100) =
        CASE
            WHEN @Question LIKE N'%tire%' OR @Question LIKE N'%puncture%' THEN N'tire'
            WHEN @Question LIKE N'%night%' OR @Question LIKE N'%visible%' THEN N'light'
            WHEN @Question LIKE N'%cold%' OR @Question LIKE N'%winter%' THEN N'warm'
            ELSE N'trail'
        END;

    DECLARE @Context nvarchar(max) =
    (
        SELECT TOP (3)
            p.ProductName,
            r.Rating,
            r.ReviewTitle,
            r.ReviewText
        FROM dbo.ProductReviews AS r
        INNER JOIN dbo.Products AS p ON p.ProductID = r.ProductID
        WHERE p.ProductName LIKE N'%' + @SearchTerm + N'%'
           OR r.ReviewText LIKE N'%' + @SearchTerm + N'%'
        ORDER BY r.Rating DESC, r.ReviewID
        FOR JSON PATH
    );

    DECLARE @Payload nvarchar(max) = JSON_OBJECT
    (
        'messages': JSON_ARRAY
        (
            JSON_OBJECT
            (
                'role': 'system',
                'content': 'Answer only from the supplied fictional product-review context. Say when evidence is insufficient.'
            ),
            JSON_OBJECT
            (
                'role': 'user',
                'content': CONCAT(N'Context: ', COALESCE(@Context, N'[]'), CHAR(10), N'Question: ', @Question)
            )
        ),
        'max_tokens': 300,
        'temperature': 0.2
    );

    SELECT
        @Context AS RetrievedContext,
        @Payload AS AugmentedPrompt,
        CASE
            WHEN OBJECT_ID(N'sys.sp_invoke_external_rest_endpoint', N'P') IS NOT NULL
                THEN N'LOCAL STOP: SQL Server exposes the REST procedure, but no approved endpoint credential is configured by this repository.'
            ELSE N'LOCAL STOP: this engine/build does not expose sys.sp_invoke_external_rest_endpoint.'
        END AS LocalDifference;
END;
GO
