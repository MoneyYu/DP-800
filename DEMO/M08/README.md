# M08 — Integrate SQL with Azure services

English | [繁體中文](README.zh-TW.md)

Provision the API surface against **AdventureGearAI** with the unified runner:

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 8
```

The runner executes `common/01-product-api.sql`, which creates read-only
`api.Categories`, `api.Products`, `api.ProductCatalog`, and
`api.InventoryAvailability` views over the canonical `catalog`/`customer` domain
data (no duplicate `ApiProducts`/`ApiCategories` tables). `common/dab-config.json`
exposes those views through REST and GraphQL and reads its connection string
from the `DATABASE_CONNECTION_STRING` environment variable only.

Follow `local/README.md` for local DAB and `azure/README.md` for managed hosting differences.
