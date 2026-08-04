# M10 — Full-text, vector, and hybrid search

English | [繁體中文](README.zh-TW.md)

Provision and run search against **AdventureGearAI** with the unified runner:

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 10
```

The runner executes `common/01-search-data.sql` (which builds
`search.SearchDocuments` from `customer.ProductReviews` joined to
`catalog.Products`, expanding the base reviews into 100+ vectorized documents so
DiskANN meets its minimum vector count) and then `local/01-search.sql`.

Full-text installation and vector syntax are detected independently. The local
script performs full-text search, EXACT vector search (`VECTOR_DISTANCE`), and
hybrid Reciprocal Rank Fusion, emitting the actual skip reason for anything the
installed build does not support. The Azure path (`azure/01-ann-search.sql`) adds
the DiskANN vector index and uses the current `SELECT TOP (...) WITH APPROXIMATE`
query syntax because preview/GA behavior can differ from local SQL Server 2025.
