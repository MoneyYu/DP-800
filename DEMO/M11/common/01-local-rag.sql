/*
    M11 common setup — local RAG prompt builder for AdventureGearAI.

    ai.usp_BuildRagPrompt retrieves grounding context from search.SearchDocuments
    (seeded by M10 from catalog.Products + customer.ProductReviews) and augments a
    chat prompt with it. Generation stays local-only: the procedure reports
    whether sys.sp_invoke_external_rest_endpoint exists but never calls out. The ai
    schema is created by the core bootstrap; the procedure is created with
    CREATE OR ALTER so this script is safe to re-run.
    M11 共用設定：AdventureGearAI 的本機 RAG 提示建立器。
    ai.usp_BuildRagPrompt 從 search.SearchDocuments 取得接地內容（由 M10 從 catalog.Products + customer.ProductReviews 植入），並用它擴充聊天提示。生成作業僅保留在本機：此預存程序會報告 sys.sp_invoke_external_rest_endpoint 是否存在，但絕不進行外部呼叫。ai 結構描述由核心 bootstrap 建立；預存程序以 CREATE OR ALTER 建立，因此此指令碼可安全地重新執行。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

CREATE OR ALTER PROCEDURE ai.usp_BuildRagPrompt
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

    /* Retrieve grounding context from the M10 search corpus (search schema),
       which is itself built from the canonical AdventureGearAI products and
       customer reviews.
       從 M10 搜尋語料庫（search 結構描述）取得接地內容；該語料庫本身是由標準 AdventureGearAI 產品和客戶評論建立。
       */
    DECLARE @Context nvarchar(max) =
    (
        SELECT TOP (3)
            d.ProductName,
            d.Rating,
            d.DocumentText
        FROM search.SearchDocuments AS d
        WHERE d.ProductName LIKE N'%' + @SearchTerm + N'%'
           OR d.DocumentText LIKE N'%' + @SearchTerm + N'%'
        ORDER BY d.Rating DESC, d.DocumentID
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

PRINT N'M11 ai.usp_BuildRagPrompt is ready (retrieves from search.SearchDocuments).';
GO
