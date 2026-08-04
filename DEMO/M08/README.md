# M08 — Integrate SQL with Azure services

English | [繁體中文](README.zh-TW.md)

Provision the API surface against **AdventureGearAI** with the unified runner:

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 8
```

The runner executes `common/01-product-api.sql`, which creates read-only
`api.Categories`, `api.Products`, `api.ProductCatalog`, and
`api.InventoryAvailability` views over the canonical `catalog`/`customer` domain
data (no duplicate `ApiProducts`/`ApiCategories` tables). The relationship-backed
`Category` and `Product` DAB entities use the canonical `catalog` tables because
the DAB CLI validates entity relationships against table metadata; the read-only
`api` views remain available to the SQL demos. `common/dab-config.json` reads its
connection string from the `DATABASE_CONNECTION_STRING` environment variable only.

The setup feature-detects and enables CDC for its owned product capture where
the platform permits it. The DAB configuration demonstrates cache settings,
entity relationships, and a stored-procedure entity without placing the
connection string in source control.

Follow `local/README.md` for local DAB and `azure/README.md` for managed hosting differences.
