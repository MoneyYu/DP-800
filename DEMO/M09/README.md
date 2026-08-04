# M09 — Models and embeddings with SQL

Provision embedding sources against **AdventureGearAI** with the unified runner:

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 9
```

The runner executes `common/01-review-data.sql` (which builds
`ai.EmbeddingDocuments` from `customer.ProductReviews` joined to
`catalog.Products`) and then `local/01-feature-detection.sql`.

The local script records the real engine/version and tests whether the `vector`
type can be used. It reports external-model and embedding work as skipped unless
the engine and an endpoint configuration support them. `azure/01-external-model.sql`
is a managed-identity template (`AdventureGearEmbeddingModel`); supply SQLCMD
variables at execution time and never commit a key, token, tenant ID, or object ID.
