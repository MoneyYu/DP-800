# M01 — Design and implement database objects

Module 1 extends the canonical **AdventureGearAI** commerce core (`catalog`,
`sales`, `customer`) with the object types covered by the module. It does not
recreate the core `catalog.Products` / `sales.Orders` entities.

## Run it

The unified demo runs through the dependency-aware hybrid runner, which ensures
the AdventureGearAI core exists and then executes this module's `common` + `local`
setup against **AdventureGearAI**:

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 1
```

To re-run after a previous Completed state, add `-Force`. The runner executes
`common/01-objects.sql` then `local/01-inspect.sql`; both are idempotent.

## What it demonstrates

- A system-versioned temporal price table (`catalog.ProductPrice` +
  `catalog.ProductPriceHistory`) sourced from `catalog.Products`.
- An indexed computed JSON projection (`catalog.Products.MetadataFrame`) over the
  canonical `ProductMetadata` document.
- A range-partitioned order teaching object (`sales.PartitionedOrders`).
- SQL graph node/edge tables (`catalog.ProductNode` / `catalog.ProductRelatedTo`)
  modelling product complements.

Azure SQL supports the core objects, but filegroup and storage decisions differ
from boxed SQL Server; see `azure/README.md`.

Module reset (`reset/reset.sql`) is provided for a later task and is not part of
the normal runner path. Legacy `DP800_Mxx` databases are never automatically
dropped; they are only reported as manual cleanup candidates.
