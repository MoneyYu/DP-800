# AdventureGearAI Single-Database Demo — Approved Design

**Status:** Approved  
**Date:** 2026-08-04  
**Scope:** Task 1 design baseline for the AdventureGearAI single-database migration

---

## 1. Goal

Replace the current eleven-database DP-800 demo layout with one scenario database named **`AdventureGearAI`**.

The logical scenario is **AdventureGear AI Commerce**: a bicycle and outdoor ecommerce workload that demonstrates catalog and inventory management, customers and orders, programmability, security and performance tuning, CI/CD and API exposure, reviews and embeddings, hybrid search, and RAG support.

Task 1 is design-and-regression only. It defines the target architecture and a RED harness. It does **not** implement the new bootstrap or module behavior yet.

---

## 2. Non-Negotiable Constraints

1. The unified demo database is named **exactly** `AdventureGearAI`.
2. Demo-owned schemas are:
   - `catalog`
   - `sales`
   - `customer`
   - `security`
   - `ops`
   - `api`
   - `search`
   - `ai`
3. The normal trainer path remains cumulative **M01 -> M11**.
4. Individual modules must also be runnable independently through **prerequisite-aware setup**.
5. State tracking is stored in:
   - `ops.DemoEnvironment`
   - `ops.DemoModuleState`
6. Module reset and full reset only affect `AdventureGearAI` and objects owned by the demo modules.
7. Existing `DP800_M01` through `DP800_M11` databases are **never** automatically dropped. They are only reported as legacy cleanup candidates.
8. Local SQL Server 2025 and Azure SQL keep the same logical scenario, but feature checks must remain truthful and platform-specific.
9. Password sourcing is limited to:
   - `DP800_SQL_PASSWORD`
   - `SQLCMDPASSWORD`
   - secure interactive prompt
10. M06 interactive concurrency work is **not** part of normal bootstrap.
11. `TERRAFORM/database-variables.tf` is out of scope and must remain untouched.

---

## 3. Target Demo Layout

### 3.1 Database contract

- Bootstrap creates or reuses **one** database: `AdventureGearAI`.
- Module scripts stop targeting `DP800_Mxx` databases.
- README execution examples point at `AdventureGearAI`.
- Legacy DP800_Mxx databases may be detected and reported, but never dropped automatically by bootstrap or reset flows.
- Legacy database names may appear only when identifying cleanup candidates; they must not remain as module execution targets.

### 3.2 Schema contract

The single database is divided by domain instead of by module:

| Schema | Responsibility |
|---|---|
| `catalog` | products, categories, inventory, merchandising |
| `sales` | orders, order lines, fulfillment, commerce transactions |
| `customer` | customer records, profiles, loyalty-style data |
| `security` | security-focused demo objects such as masked or policy-backed surfaces |
| `ops` | environment markers, module state, reset bookkeeping |
| `api` | API-facing views, tables, and procedures used by Data API Builder |
| `search` | hybrid search structures and search-facing projections |
| `ai` | reviews, embeddings, RAG, AI-oriented projections |

---

## 4. Bootstrap and Module Flow

### 4.1 Normal bootstrap

The default bootstrap path prepares the cumulative scenario from M01 through M11, while preserving truthful platform detection for local SQL Server 2025 and Azure SQL.

Bootstrap must stop using the current eleven-database pattern and instead converge the environment into `AdventureGearAI`.

### 4.2 Independent module execution

Each module remains independently runnable, but setup becomes prerequisite-aware:

- Running a later module automatically ensures its required earlier shared structures exist.
- Re-running a module must be idempotent for module-owned objects where practical.
- M06 interactive concurrency remains opt-in and excluded from normal bootstrap because it depends on multi-session trainer interaction.

### 4.3 Expected bootstrap asset contract

Future implementation work must introduce these bootstrap assets:

- `DEMO/bootstrap/00-create-adventuregear-database.sql`
- `DEMO/bootstrap/01-initialize-adventuregear-demo.sql`

`Invoke-Bootstrap.ps1` remains the orchestrator, but these assets become the single-database foundation that the RED harness expects.

---

## 5. State Tracking and Reset Rules

### 5.1 Environment markers

`ops.DemoEnvironment` records the active demo environment marker for `AdventureGearAI`.

`ops.DemoModuleState` records module-level setup/reset state so prerequisite-aware execution can determine what must be created, skipped, refreshed, or reported.

### 5.2 Reset behavior

Two reset levels are required:

- **Module reset:** removes or rebuilds only the owning module’s objects inside `AdventureGearAI`
- **Full reset:** resets the AdventureGearAI demo environment in a way that is hard-scoped to `AdventureGearAI`

Module reset scripts must no longer use `DROP DATABASE`.

Future implementation work must introduce this full reset entry point:

- `DEMO/reset/Reset-AdventureGearAI.ps1`

The full reset wrapper is a thin PowerShell orchestrator: it connects with `-Database master` and runs its destructive work from a single, known literal SQL asset:

- `DEMO/reset/reset-adventuregear.sql`

The regression harness inspects both the wrapper and this SQL asset. It rejects a non-literal reset SQL path, dynamic destructive SQL (`EXEC`/`sp_executesql`), and any literal `ALTER DATABASE`/`DROP DATABASE` target other than `AdventureGearAI`.

No reset flow may automatically drop legacy `DP800_Mxx` databases.

---

## 6. API, Search, and AI Contracts

### 6.1 Data API Builder

The DAB configuration must stop sourcing `dbo.ApiProducts` and `dbo.ApiCategories`.

The approved direction is to point DAB at domain-schema sources in the `api` schema, with the API contract owned by AdventureGearAI rather than ad hoc `dbo` staging tables. At minimum:

- `Category` sources `api.Categories`
- `Product` sources `api.Products`
- `ProductCatalog` sources `api.ProductCatalog`

### 6.2 CI/CD publish target

The SQL project publish profile must target `AdventureGearAI` instead of `DP800_M07`.

### 6.3 Search and RAG

Reviews, embeddings, hybrid search, and RAG support all live inside the `AdventureGearAI` scenario through the `ai`, `search`, and `api` surfaces instead of separate per-module databases.

---

## 7. Platform Truthfulness

The unified design keeps one logical commerce scenario across local SQL Server 2025 and Azure SQL, but implementation must preserve honest feature detection:

- local-only behavior remains local-only
- Azure-only behavior remains Azure-only
- preview or optional capabilities must be detected and reported instead of assumed

The single-database design unifies the story, not the platform claims.

---

## 8. Task 1 Deliverables

Task 1 produces:

1. This approved design specification
2. `DEMO/tests/Test-UnifiedDemo.ps1` as a deterministic structural regression harness

The harness is intentionally **RED** at this task boundary because the repository still contains the eleven-database architecture.

Required RED checks include:

- bootstrap still must be migrated away from `DP800_Mxx` (including dynamic `EXEC`/`sp_executesql` name construction)
- AdventureGearAI bootstrap assets are not yet present
- marker/state definitions are not yet present
- README targets still mention `DP800_Mxx` (harness scans every README recursively under `DEMO`, excluding `DEMO/tests`, and only permits explicit legacy manual-cleanup prose)
- module resets still use `DROP DATABASE`
- DAB still targets `dbo.ApiProducts` and `dbo.ApiCategories`
- the SQL publish profile still targets `DP800_M07`
- the full reset entry point (`Reset-AdventureGearAI.ps1` wrapper plus its `reset-adventuregear.sql` asset) does not yet exist

---

## 9. Out of Scope for Task 1

- Implementing the unified database
- Rewriting module SQL scripts
- Rewriting DAB entities
- Rewriting the SQL project
- Changing Terraform files
- Dropping any existing `DP800_Mxx` database automatically

Task 1 is complete when the spec is committed and the RED harness is committed, parsed, executed, and shown failing for the intended architectural reasons.

