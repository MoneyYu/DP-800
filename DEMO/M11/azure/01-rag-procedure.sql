:setvar AzureOpenAIEndpointName "REPLACE_AT_RUNTIME"
:setvar ChatDeploymentName "REPLACE_AT_RUNTIME"

CREATE OR ALTER PROCEDURE dbo.usp_AskProductQuestion
    @Question nvarchar(1000),
    @Answer nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Context nvarchar(max) =
    (
        SELECT TOP (5)
            p.ProductName,
            r.Rating,
            r.ReviewTitle,
            r.ReviewText
        FROM dbo.ProductReviews AS r
        INNER JOIN dbo.Products AS p ON p.ProductID = r.ProductID
        ORDER BY r.Rating DESC, r.ReviewID
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

