# M01 — Design and implement database objects

English | [繁體中文](README.zh-TW.md)

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
`common/01-objects.sql`, `common/02-specialized-tables.sql`,
`local/01-inspect.sql`, and `local/02-inspect-specialized.sql`; all are
idempotent.

## What it demonstrates

- A system-versioned temporal price table (`catalog.ProductPrice` +
  `catalog.ProductPriceHistory`) sourced from `catalog.Products`.
- An indexed computed JSON projection (`catalog.Products.MetadataFrame`) over the
  canonical `ProductMetadata` document.
- A range-partitioned order teaching object (`sales.PartitionedOrders`).
- SQL graph node/edge tables (`catalog.ProductNode` / `catalog.ProductRelatedTo`)
  modelling product complements.
- Native `json` columns, a `CREATE JSON INDEX` preview feature in SQL Server
  2025, and `JSON_VALUE`, `JSON_PATH_EXISTS`, `JSON_CONTAINS`, and `.modify()`
  operations.
- An In-Memory OLTP cache, an updatable ledger table, a sequence allocation
  table, and constraint violations captured as teaching data.
- Feature-detected PolyBase external-table metadata only; it never queries
  external data or stores credentials.

The deterministic classroom seed has **10 categories, 150 products, 120
customers, 800 orders, 2,400 order items, and 500 reviews**. This data volume
is separate from feature detection: the same rows are always seeded, while
In-Memory OLTP, PolyBase, and Full-Text Search availability depends on the
installed engine/image.

The M01 reset removes the In-Memory table but intentionally retains its
memory-optimized filegroup/container, because removing it can hang a
containerized SQL Server instance. Dropping the updatable ledger can retain an
engine-managed dropped-ledger table for verification; that behavior is expected.
Use the [custom FTS/PolyBase Docker image](../docker/README.md) when the
Full-Text Search and PolyBase demonstrations are required.

Azure SQL supports the core objects, but filegroup and storage decisions differ
from boxed SQL Server; see `azure/README.md`.

Module reset (`reset/reset.sql`) is provided for a later task and is not part of
the normal runner path. Legacy `DP800_Mxx` databases are never automatically
dropped; they are only reported as manual cleanup candidates.
