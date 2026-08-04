# DP-800 trainer demos — the AdventureGearAI course flow

English | [繁體中文](README.zh-TW.md)

This folder is a compact, resettable trainer path aligned to the 11 DP-800
modules. Every module now teaches against **one** database, literally named
`AdventureGearAI`, instead of eleven isolated `DP800_Mxx` databases. Local SQL
Server 2025 behavior and Azure SQL behavior are kept distinct, and the local
container is always managed outside this repository.

## The AdventureGear AI Commerce story

AdventureGear is a fictional outdoor-gear retailer. Across three teaching days
the class grows a single commerce database — from core schema and programmability
into security, performance, CI/CD, an API surface, and finally embeddings,
intelligent search, and RAG. The story is deliberately cumulative: the products,
customers, orders, and reviews created on Day 1 are the same rows the AI modules
retrieve and ground against on Day 3.

The bootstrap provisions eight domain schemas inside `AdventureGearAI`:

| Schema | Purpose |
|---|---|
| `catalog` | Products, categories, inventory, and the M01/M03 object demos (temporal price, JSON projection, partitioning, graph). |
| `sales` | Orders, order items, and the M02 programmability objects (views, procedures, functions, triggers). |
| `customer` | Customers and product reviews — the source rows for M09/M10/M11. |
| `security` | M05 secured projection, Dynamic Data Masking, and Row-Level Security policy. |
| `ops` | Operational tracking (`ops.DemoEnvironment`, `ops.DemoModuleState`) plus the M03/M06 teaching objects. |
| `api` | M08 read-only views exposed through Data API Builder (REST/GraphQL). |
| `search` | M10 search documents built from catalog products and customer reviews. |
| `ai` | M09 embedding documents and the M11 RAG prompt/procedure surface. |

The canonical seed (created once by the bootstrap) has **10 categories, 150
products, 120 customers, 800 orders, 2,400 order items, and 500 reviews**.
Modules extend this core; they never recreate it. This deterministic data volume
is independent of feature detection: native `json` and JSON index operations
can be taught from the same seed even when In-Memory OLTP, Ledger, Sequence,
PolyBase, Full-Text Search, or another installed feature is unavailable.

M01 adds native JSON, a preview SQL Server 2025 JSON index, In-Memory OLTP,
Ledger, Sequence, and feature-detected PolyBase external metadata. Its reset
keeps the memory-optimized filegroup/container (removing it can hang a
container) and may leave an engine-managed dropped-ledger table after a Ledger
drop; both are intentional. Use the [custom FTS/PolyBase Docker image](docker/README.md)
when Full-Text Search or PolyBase is needed.

## Local connection

| Setting | Value |
|---|---|
| Container | `mssql2025` (managed outside this repository) |
| Address | `127.0.0.1:1433` (`127.0.0.1,1433` for `sqlcmd`) |
| Login | `sa` |
| Password | `DP800_SQL_PASSWORD`, then `SQLCMDPASSWORD`, otherwise a secure prompt |

The repository never creates, starts, stops, removes, or persists the container.
Never put the SA password in a script, command argument, connection string,
`.env` file, or Git history.

## Bootstrap and run modules

PowerShell 7 and `sqlcmd` are required. Run every command from the repository
root with `$env:DP800_SQL_PASSWORD` set.

### Core-only bootstrap

Provision just the single `AdventureGearAI` database — its schemas, the
`ops.DemoEnvironment` marker, the `ops.DemoModuleState` rows, and the canonical
ecommerce seed — without running any module:

```powershell
pwsh -NoProfile -File DEMO/bootstrap/Invoke-Bootstrap.ps1
```

### Run one, several, or all modules

Modules run through the dependency-aware hybrid runner. Both entry points ensure
the core exists first and then execute each module's `common` + `local` setup
against `AdventureGearAI`. Requesting modules on the bootstrap simply delegates to
the same runner:

```powershell
# One module (bootstrap delegates to the runner):
pwsh -NoProfile -File DEMO/bootstrap/Invoke-Bootstrap.ps1 -Modules 1

# Several modules (order-independent; dependencies auto-resolve):
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 5,6,7

# All eleven modules in dependency order:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1
```

`Invoke-DemoModule.ps1` with no `-Modules` runs M01–M11. A module that is already
`Completed` is skipped; add `-Force` to re-run it:

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 2 -Force
```

## Operational tracking and dependency resolution

Two `ops` tables make the single database self-describing and idempotent:

- **`ops.DemoEnvironment`** — a singleton marker row that pins the database to
  `AdventureGearAI` and records the demo name, schema version, and init time. The
  SQL guard (`scripts/Assert-DemoDatabase.sql`) refuses to run module or reset
  scripts unless this marker is present, so nothing destructive can run against
  the wrong database.
- **`ops.DemoModuleState`** — one row per module (M01–M11) tracking `NotStarted`,
  `Running`, `Completed`, or `Failed`. The runner reads this state to skip
  completed modules (unless `-Force`) and records success/failure per module.

The runner resolves prerequisites automatically from a dependency graph:

- **Cumulative M01 → M11 path.** M01 builds on the core; M02–M09 build on
  M01; M10 builds on M01 + M09; M11 builds on M01 + M09 + M10. Requesting a
  later module transitively pulls in and runs its prerequisites first, in a
  deterministic topological order (ascending module number as the tiebreak). For
  example, `-Modules 11` runs M01 → M09 → M10 → M11 so `search.SearchDocuments`
  is seeded before M11 reads it.
- **Independent module path.** Modules that depend only on the core plus M01
  (M02–M08) can be run individually in any order; requesting a single one runs
  the core, then M01, then that module.

## Reset workflows

There are two reset scopes, and neither drops a `DP800_Mxx` database.

### Module reset (scoped)

Each module ships `reset/reset.sql`, which removes only the objects that module
owns and returns that module — plus every dependent module — to `NotStarted` in
`ops.DemoModuleState`. The canonical `catalog`/`sales`/`customer` core is left
intact. Run it against `AdventureGearAI`:

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M01/reset/reset.sql
```

Because every module depends transitively on M01, resetting M01 marks M02–M11
stale so the runner reapplies them from a clean baseline.

### Full reset (database-level)

The only script permitted to drop a database is hard-scoped to the literal
`AdventureGearAI`. The wrapper rolls back active sessions, drops the database, and
re-runs the core bootstrap:

```powershell
pwsh -NoProfile -File DEMO/reset/Reset-AdventureGearAI.ps1
```

## Legacy DP800_Mxx databases

Earlier iterations of this demo created one legacy database per module named
`DP800_M01` through `DP800_M11` (manual cleanup candidates). The unified demo
owns only `AdventureGearAI` and never creates, alters, or drops those databases.
If they still exist from a previous run, the bootstrap merely reports them (via
`bootstrap/report-legacy-databases.sql`) as manual cleanup candidates that are
never automatically deleted. Remove them by hand only if you choose to; no demo
command targets a legacy `DP800_Mxx` database (manual cleanup only, never
automatically deleted).

## Local and Azure matrix

| Module | Local SQL Server 2025 | Azure path |
|---|---|---|
| M01 objects | Native JSON/preview JSON index, temporal, In-Memory, Ledger, Sequence, partitioning, graph, and feature-detected PolyBase over `catalog` | Same core syntax; service-tier/storage choices differ |
| M02 programmability | Views, procedures, functions, triggers in `sales` | Same core objects |
| M03 advanced T-SQL | CTE, windows, JSON, fuzzy, graph, error handling; regex detected | Azure SQL supports the documented regex surface by service/version |
| M04 AI-assisted workflow | Offline prompt/review exercise over `sales`/`customer`; no Copilot API dependency | Use approved Copilot/Fabric tooling and identity controls |
| M05 security | DDM and RLS execute in `security`; TDE/Always Encrypted are inspected/explained | TDE is platform-managed; Entra and auditing are Azure paths |
| M06 performance | Query Store, plans, DMVs; blocking/deadlock scripts are **interactive** and excluded from the runner (run by hand in multiple sessions) | Service tiers and Query Performance Insight are Azure-only |
| M07 CI/CD | SDK SQL project **builds** a dacpac targeting `AdventureGearAI`; optional local **publish** via the passwordless Entra profile | GitHub Actions sample uses repository secrets/OIDC |
| M08 Data API Builder | DAB serves `api.*` views from a local connection string in the environment | Managed identity and Azure hosting are documented separately |
| M09 models/embeddings | `vector` and external-model catalog feature-detected; **external REST/model generation** is skipped without an approved endpoint/credential | Managed identity plus `CREATE EXTERNAL MODEL` template |
| M10 intelligent search | Full-text and exact `VECTOR_DISTANCE` demos when installed/supported; ANN is truthfully skipped when the local build lacks the **vector index** surface | DiskANN/`VECTOR_SEARCH` requires supported Azure/preview configuration |
| M11 RAG | Builds retrieval context/prompt from `search`; **external REST** execution is feature-detected and needs an approved endpoint credential | Azure REST generation path uses managed identity and Azure SQL |

Unsupported or preview features must report a real detection result. Do not treat
SQL Server 2025 and Azure SQL as interchangeable.
