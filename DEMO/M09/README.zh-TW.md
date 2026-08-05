繁體中文 | [English](README.md)

# M09 — 使用 SQL 的模型與內嵌

使用統一執行器，針對 **AdventureGearAI** 佈建內嵌來源：

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 9
```

執行器會執行 `common/01-review-data.sql`（它從 `customer.ProductReviews` 與 `catalog.Products` 的聯結建立 `ai.EmbeddingDocuments`），接著執行 `local/01-feature-detection.sql`。

本機指令碼會記錄實際的引擎／版本，並測試是否可使用 `vector` 型別。`local/01-feature-detection.sql` 只會探測 `sys.external_models`；由於存放庫沒有已核准的端點或認證，本機會略過外部模型建立與 `AI_GENERATE_EMBEDDINGS`。`azure/01-external-model.sql` 是受控識別範本（`AdventureGearEmbeddingModel`）；請在執行時提供 SQLCMD 變數及已核准的端點，絕不可認可金鑰、權杖、租用戶 ID 或物件 ID。
