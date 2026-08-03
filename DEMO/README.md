# DP-800 trainer demos

This folder is a compact, resettable trainer path aligned to the 11 DP-800 modules. It uses fictional ecommerce data and keeps local SQL Server 2025 behavior separate from Azure SQL behavior.

## Local connection

| Setting | Value |
|---|---|
| Container | `mssql2025` (managed outside this repository) |
| Address | `127.0.0.1:1433` (`127.0.0.1,1433` for `sqlcmd`) |
| Login | `sa` |
| Password | `DP800_SQL_PASSWORD`, then `SQLCMDPASSWORD`, otherwise a secure prompt |

The repository never creates, starts, stops, removes, or persists the container. Never put the SA password in a script, command argument, connection string, `.env` file, or Git history.

## Bootstrap and reset

PowerShell 7 and `sqlcmd` are required.

```powershell
pwsh DEMO/bootstrap/Invoke-Bootstrap.ps1
pwsh DEMO/scripts/Invoke-Dp800Sql.ps1 -Database DP800_M01 -InputFile DEMO/M01/common/01-objects.sql
pwsh DEMO/scripts/Invoke-Dp800Sql.ps1 -Database master -InputFile DEMO/M01/reset/reset.sql
pwsh DEMO/bootstrap/Invoke-Bootstrap.ps1 -Modules 1
```

Bootstrap only creates databases named `DP800_M01` through `DP800_M11`. Each reset script only drops its matching `DP800_` database. Re-run bootstrap after reset, then run the module's `common/` and `local/` scripts in filename order.

## Local and Azure matrix

| Module | Local SQL Server 2025 | Azure path |
|---|---|---|
| M01 objects | Tables, indexes, temporal, JSON, partitioning, graph | Same core syntax; service-tier/storage choices differ |
| M02 programmability | Views, procedures, functions, triggers | Same core objects |
| M03 advanced T-SQL | CTE, windows, JSON, fuzzy, graph, error handling; regex detected | Azure SQL supports the documented regex surface by service/version |
| M04 AI-assisted workflow | Offline prompt/review exercise; no Copilot API dependency | Use approved Copilot/Fabric tooling and identity controls |
| M05 security | DDM and RLS execute; TDE/Always Encrypted are inspected/explained | TDE is platform-managed; Entra and auditing are Azure paths |
| M06 performance | Query Store, plans, DMVs, blocking/deadlock scripts | Service tiers and Query Performance Insight are Azure-only |
| M07 CI/CD | SDK SQL project build and optional local publish | GitHub Actions sample uses repository secrets/OIDC |
| M08 Data API Builder | DAB can use a local connection string from the environment | Managed identity and Azure hosting are documented separately |
| M09 models/embeddings | Vector and AI syntax are feature-detected; no endpoint is assumed | Managed identity plus `CREATE EXTERNAL MODEL` template |
| M10 intelligent search | Full-text and exact vector demos when installed/supported | DiskANN/`VECTOR_SEARCH` requires supported Azure/preview configuration |
| M11 RAG | Builds retrieval context/prompt; REST execution is feature-detected and needs an approved endpoint credential | Azure REST generation path uses managed identity and Azure SQL |

Unsupported or preview features must report a real detection result. Do not treat SQL Server 2025 and Azure SQL as interchangeable.
