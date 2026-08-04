繁體中文 | [English](README.md)

# M11 — 使用 SQL 的 RAG

使用統一執行器，針對 **AdventureGearAI** 佈建並執行本機 RAG 路徑：

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 11
```

執行器會解析相依性鏈結（M01 → M09 → M10 → M11），因此 M11 執行前，`search.SearchDocuments` 已完成植入。它會執行 `common/01-local-rag.sql`（它會建立 `ai.usp_BuildRagPrompt`，從 `search.SearchDocuments` 擷取基礎脈絡），接著執行 `local/01-build-prompt.sql`。

本機路徑示範擷取、native JSON nested grounding context 和提示建構。它會對單一
grounded product 使用 `FOR JSON PATH, WITHOUT_ARRAY_WRAPPER`，將 `ProductMetadata`
保留為 nested JSON，而非逸出成字串。SQL Server 2025 可公開
`sp_invoke_external_rest_endpoint`，因此程序會回報它是否存在；除非已設定核准的端點與
資料庫範圍認證，否則仍會略過外部 REST 產生。`azure/01-rag-procedure.sql`
（`ai.usp_AskProductQuestion`）會以執行階段 SQLCMD 變數示範受控識別 REST 模式。
