:setvar AzureOpenAIEndpointName "REPLACE_AT_RUNTIME"
:setvar ChatDeploymentName "REPLACE_AT_RUNTIME"

CREATE OR ALTER PROCEDURE ai.usp_AskProductQuestion
    @Question nvarchar(1000),
    @Answer nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    /* Retrieve grounding context from the M10 search corpus (search schema),
       which is built from the canonical AdventureGearAI products and reviews.
       從 M10 搜尋語料庫（search 結構描述）取得接地內容；語料庫由標準 AdventureGearAI 產品和評論建立。
       */
    DECLARE @Context nvarchar(max) =
    (
        SELECT TOP (5)
            d.ProductName,
            d.Rating,
            d.DocumentText
        FROM search.SearchDocuments AS d
        ORDER BY d.Rating DESC, d.DocumentID
        FOR JSON PATH
    );

    DECLARE @Payload nvarchar(max) = JSON_OBJECT
    (
        'messages': JSON_ARRAY
        (
            JSON_OBJECT('role': 'system', 'content': 'Answer only from the supplied product-review context.'),
            JSON_OBJECT('role': 'user', 'content': CONCAT(N'Context: ', @Context, CHAR(10), N'Question: ', @Question))
        ),
        'max_tokens': 300,
        'temperature': 0.2
    );
    DECLARE @Response nvarchar(max);
    DECLARE @ReturnValue int;

    EXEC @ReturnValue = sys.sp_invoke_external_rest_endpoint
        @url = N'https://$(AzureOpenAIEndpointName).openai.azure.com/openai/deployments/$(ChatDeploymentName)/chat/completions?api-version=2024-10-21',
        @method = N'POST',
        @credential = [https://$(AzureOpenAIEndpointName).openai.azure.com],
        @payload = @Payload,
        @response = @Response OUTPUT;

    IF @ReturnValue = 0
        SET @Answer = JSON_VALUE(@Response, '$.result.choices[0].message.content');
    ELSE
        THROW 51110, 'Azure OpenAI REST invocation failed; inspect the response and managed-identity permissions.', 1;
END;
GO
