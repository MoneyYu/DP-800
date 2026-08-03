# Azure RAG path

1. Run in Azure SQL Database, not the local SQL Server container.
2. Create the endpoint database scoped credential with managed identity outside this repository.
3. Grant the database identity access to the approved Azure OpenAI deployments.
4. Grant the caller only the required procedure permission; `EXECUTE ANY EXTERNAL ENDPOINT` is powerful.
5. Supply endpoint/deployment SQLCMD variables at runtime and never commit a key, token, tenant ID, or object ID.
6. For semantic retrieval, replace the compact rating-based retrieval query with the supported M09/M10 embedding and vector-search path.

