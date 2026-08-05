:setvar AzureOpenAIEndpointName "REPLACE_AT_RUNTIME"
:setvar EmbeddingDeploymentName "text-embedding-3-small"

SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'AdventureGearEmbeddingModel')
    DROP EXTERNAL MODEL AdventureGearEmbeddingModel;
GO

CREATE EXTERNAL MODEL AdventureGearEmbeddingModel
WITH
(
    LOCATION = 'https://$(AzureOpenAIEndpointName).openai.azure.com/openai/deployments/$(EmbeddingDeploymentName)/embeddings?api-version=2024-10-21',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = '$(EmbeddingDeploymentName)',
    CREDENTIAL = [https://$(AzureOpenAIEndpointName).openai.azure.com]
);
GO

-- The referenced database scoped credential must be created separately with managed identity.
-- 所參考的資料庫範圍認證必須以受控識別另外建立。
-- No API key, tenant ID, object ID, or token belongs in this file.
-- 此檔案不得包含 API 金鑰、租用戶 ID、物件 ID 或權杖。
