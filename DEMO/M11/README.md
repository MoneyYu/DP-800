# M11 — RAG with SQL

English | [繁體中文](README.zh-TW.md)

Provision and run the local RAG path against **AdventureGearAI** with the unified runner:

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 11
```

The runner resolves the dependency chain (M01 → M09 → M10 → M11), so
`search.SearchDocuments` is already seeded before M11 runs. It executes
`common/01-local-rag.sql` (which creates `ai.usp_BuildRagPrompt`, retrieving
grounding context from `search.SearchDocuments`) and then
`local/01-build-prompt.sql`.

The local path demonstrates retrieval, a native JSON nested grounding context,
and prompt construction. It uses `FOR JSON PATH, WITHOUT_ARRAY_WRAPPER` for the
single grounded product, preserving `ProductMetadata` as nested JSON rather than
an escaped string.
SQL Server 2025 can expose `sp_invoke_external_rest_endpoint`, so the procedure
reports whether it exists; generation is still skipped unless an approved
endpoint and database scoped credential are configured. `azure/01-rag-procedure.sql`
(`ai.usp_AskProductQuestion`) shows the managed-identity REST pattern with runtime
SQLCMD variables.
