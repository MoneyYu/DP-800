繁體中文 | [English](README.md)

# M10 — 全文、向量與混合式搜尋

使用統一執行器，針對 **AdventureGearAI** 佈建並執行搜尋：

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 10
```

執行器會執行 `common/01-search-data.sql`（它從 `customer.ProductReviews` 與 `catalog.Products` 的聯結建立 `search.SearchDocuments`，並將基本評論擴展為 100 多個向量化文件，使 DiskANN 達到其最少向量數量），接著執行 `local/01-search.sql`。

全文搜尋安裝與向量語法會分別偵測。本機指令碼會執行 `CONTAINS` 和 `FREETEXT`
全文搜尋、精確向量搜尋（`VECTOR_DISTANCE`）與混合式 Reciprocal Rank Fusion，並為已安裝組建
不支援的任何項目輸出實際略過原因；它不會宣稱本機具有 ANN 功能。Azure 路徑
（`azure/01-ann-search.sql`）會新增 DiskANN 向量索引，並使用目前的
`SELECT TOP (...) WITH APPROXIMATE` 查詢語法，因為預覽版／GA 行為可能與本機 SQL Server
2025 不同；DiskANN 需要適當的 Azure 設定與索引建立才能使用。

只有安裝 Full-Text Search 時才會執行 `FREETEXT`。本機全文與 PolyBase 示範請使用
[custom FTS/PolyBase Docker image](../docker/README.md)；標準 image 則會回報
feature-detected skip。
