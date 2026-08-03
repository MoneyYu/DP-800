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
-- No API key, tenant ID, object ID, or token belongs in this file.
