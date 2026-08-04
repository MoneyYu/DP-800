# DP-800 demo environment reference

## Purpose and source alignment

The repository contains two complementary trainer paths:

1. [TERRAFORM](../TERRAFORM/) provisions an Azure backup environment.
2. [DEMO](../DEMO/) targets an existing local SQL Server 2025 container for compact, resettable exercises.

The implemented Azure scope follows the DP-800 decks and speaker notes under [PPT/DP-800](../PPT/DP-800/): Azure SQL Database and Managed Instance platform choices, security/operations, SQL Server 2025, and the modules 09–11 progression from external models and embeddings to DiskANN/hybrid search and RAG. This document describes the code as implemented; it does not claim that Azure apply/destroy testing has completed.

## Terraform baseline and geography

| Item | Implemented state |
|---|---|
| Terraform | `>= 1.9.0` |
| AzureRM | `>= 5.0.1, < 6.0.0` |
| Other providers | AzAPI `~> 2.11`, Random `~> 3.9`, HTTP `~> 3.6` |
| Default location | `japaneast` |
| AI override | `ai_location`; affects Azure OpenAI/model placement only |
| Database Watcher | Preview resource fixed to `Japan West` with `Microsoft.DatabaseWatcher/watchers@2024-10-01-preview` (Japan East is not a supported region; verify the API version with `az provider show --namespace Microsoft.DatabaseWatcher`) |

The common `DP800-<group_postfix>` resource group is always declared. The AI resources use a separate `DP800-<group_postfix>-AI` resource group; its SQL server/database remain in `location`, while Azure OpenAI uses `ai_location` when supplied.

## Retained database gallery

All main feature toggles default to `true`, so the default plan retains the broad gallery:

| Toggle | Resources currently declared |
|---|---|
| `enable_azure_sql_gallery` | Password-auth Azure SQL logical server; S1 database; Standard 100-DTU elastic pool with two databases; `HS_Gen5_2` Hyperscale database; storage, managed-identity auditing, firewall rules, and security alert policy. |
| `enable_sql_managed_instance` | SQL Managed Instance `GP_Gen5`, 4 vCores, 32 GB storage, public endpoint, system identity, and dedicated networking. |
| `enable_sql_vm_2019` | SQL Server 2019 Developer VM on Windows Server 2019, `Standard_B4ms`, PAYG SQL VM registration, premium 256-GB data and 128-GB log disks, patching and assessment. |
| `enable_sql_vm_2022` | SQL Server 2022 Developer VM on Windows Server 2022, `Standard_B2s`, PAYG SQL VM registration, premium 256-GB data and 128-GB log disks, patching and assessment. |
| `enable_postgresql_flexible` | PostgreSQL Flexible Server 16, `B_Standard_B1ms`, 32 GB, password authentication, database, firewall rule, and Sunday maintenance window. |
| `enable_operations` | Database Watcher preview, Key Vault Standard with RBAC authorization and deployer `Key Vault Secrets Officer`, and a system-identity Automation account. |

When operations, gallery, and `enable_azure_services_firewall_demo` are all enabled, Automation also creates a password-based credential, a PowerShell 5.1 Runtime Environment-linked SQL maintenance runbook, daily schedule, and job schedule against the second elastic-pool database. The scheduled `SqlPassword` path uses the `Get-AutomationPSCredential` internal cmdlet, which is available in the system-generated PowerShell 5.1 environment but not in a custom PowerShell 7.6 Runtime Environment. PowerShell 7.6 was verified as GA for Azure Automation public regions on 2026-08-04, but requires a managed-identity or Key Vault redesign before this runbook can use it. If gallery or the broad Azure-services firewall demonstration is disabled, those maintenance objects are omitted while the base operations resources remain.

The Hyperscale gallery database does not specify `max_size_gb`: Hyperscale databases have no defined maximum size and grow as needed, so configuring that value causes a perpetual Terraform diff without enforcing a storage limit.

SQL VM patching is owned by the SQL IaaS Agent `auto_patching` block on `azurerm_mssql_virtual_machine`. `MicrosoftSQLServer` marketplace images are not in the [supported image list for Automatic VM Guest Patching](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching#supported-os-images), so `AutomaticByPlatform` is rejected by ARM. Both virtual machines therefore use `patch_mode = "Manual"` with `automatic_updates_enabled = false`, because running two overlapping patching mechanisms is explicitly discouraged.

`enable_legacy_key_auth_demo=false` is intentional. Setting it true re-enables retained storage-key paths for SQL auditing/VM automated backup where the associated gallery and VM resources exist; it is not part of the default managed-identity/RBAC posture.

### Password boundary

`admin_password` is required only when at least one of these password-based features is enabled:

- Azure SQL gallery;
- SQL Managed Instance;
- SQL VM 2019;
- SQL VM 2022;
- PostgreSQL Flexible Server.

The Automation SQL maintenance credential is created only with the gallery, so it inherits the gallery password requirement. Never store the password in the repository. AI-only, operations-only without gallery maintenance, and all-main-features-disabled plans are password-free. See the secure process-environment example in [TERRAFORM/README.md](../TERRAFORM/README.md#secure-password-input).

### Cost and duration

The defaults are intentionally comprehensive, not economical. SQL Managed Instance, both SQL VMs and their premium disks, Hyperscale, the Standard elastic pool, PostgreSQL, Azure OpenAI, Database Watcher preview, Key Vault, and Automation can all incur charges.

SQL Managed Instance is especially slow to create and delete compared with the other resources. Plan a long deployment/teardown window, monitor Azure rather than interrupting Terraform, and destroy the environment after testing. This warning documents the defaults; it does not change them.

## Independent SQL AI stack

`enable_core_sql_ai=true` creates an independent stack that has no password dependency:

| Component | Implemented state |
|---|---|
| Azure SQL | Entra-only logical server, system-assigned identity, TLS 1.2, deployer IP firewall rule |
| Database | `dp800-ai-rag`, serverless General Purpose `GP_S_Gen5_2`, 32 GB maximum, 0.5 minimum vCore, 60-minute auto-pause |
| Azure OpenAI | Kind `OpenAI`, S0, custom subdomain, public endpoint, system identity, `local_auth_enabled=false` |
| Embedding | `text-embedding-3-small`, version `1`, default deployment SKU `GlobalStandard`, `VECTOR(1536)` |
| Chat | `gpt-5.4-mini`, version `2026-03-17`, `GlobalStandard` |
| Authorization | SQL server identity and deployer receive `Cognitive Services OpenAI User` |
| Output | Resource names/endpoints and deployment names only; no password, key, token, or secret |

The chat deployment is sequenced after the embedding deployment to avoid concurrent deployment writes. Both versions use `NoAutoUpgrade`.

The model/region tuple reflects the implementation validated on 2026-08-03. Immediately before delivery, recheck lifecycle, GA status, exact model version, deployment type, `japaneast` or override availability, and subscription quota in the current [Foundry model catalog and region availability](https://learn.microsoft.com/azure/ai-foundry/openai/concepts/models). Region availability does not guarantee subscription quota or live capacity.

## AI data plane

[sample-data/ecommerce-ai.sql](../TERRAFORM/sample-data/ecommerce-ai.sql) is run by [Deploy-AiDataPlane.ps1](../TERRAFORM/scripts/Deploy-AiDataPlane.ps1) when `enable_core_sql_ai && enable_data_plane`.

It implements the course sequence:

1. Enables compatibility level 170 and the required preview/vector database-scoped settings.
2. Creates a managed-identity database scoped credential. No API key is present.
3. Creates `DP800_EmbeddingModel` with `CREATE EXTERNAL MODEL` against the embedding deployment.
4. Creates six fictional ecommerce products and 104 fictional reviews: eight base reviews plus twelve variants of each base row.
5. Generates and stores `text-embedding-3-small` vectors in `VECTOR(1536)`.
6. Creates the current preview DiskANN form:

   ```sql
   CREATE VECTOR INDEX IX_ai_ProductReview_ReviewVector
   ON dbo.ai_ProductReview(ReviewVector)
   WITH (METRIC = 'cosine', TYPE = 'DISKANN');
   ```

7. Queries DiskANN through `VECTOR_SEARCH` with `SELECT TOP (...) WITH APPROXIMATE`, matching the current [VECTOR_SEARCH preview syntax](https://learn.microsoft.com/sql/t-sql/functions/vector-search-transact-sql?view=sql-server-ver17).
8. Creates a full-text catalog/index, uses `FREETEXTTABLE`, and merges keyword/vector rankings with reciprocal rank fusion (RRF).
9. Builds JSON retrieval context and invokes the chat deployment with `sys.sp_invoke_external_rest_endpoint` for REST RAG.

The relevant Microsoft references are [CREATE EXTERNAL MODEL](https://learn.microsoft.com/sql/t-sql/statements/create-external-model-transact-sql?view=sql-server-ver17) and [CREATE VECTOR INDEX (preview)](https://learn.microsoft.com/sql/t-sql/statements/create-vector-index-transact-sql?view=sql-server-ver17). These features and syntax remain version/preview sensitive.

### Identity prerequisites and propagation

The applying workstation must have PowerShell 7 and Azure CLI. No `SqlServer` PowerShell module is required: the deployment script executes the SQL script through the `System.Data.SqlClient` types bundled with PowerShell 7. Azure CLI must be signed in as the configured SQL Entra administrator identity.

The deployment script requests an Azure SQL token, reads the JWT `oid`, and compares it with `DP800_SQL_ADMIN_OBJECT_ID`. A mismatch stops deployment before SQL execution. It then verifies the SQL server managed identity and OpenAI RBAC assignment, waits for propagation, and retries identity-related `401`/`403` errors. This is an Entra token and managed-identity path only; no Azure OpenAI API keys are supported.

## Local Docker path

The local path uses an existing container named `mssql2025`, managed outside this repository:

| Setting | Value |
|---|---|
| Endpoint | `127.0.0.1:1433` (`127.0.0.1,1433` for `sqlcmd`) |
| Login | `sa` |
| Password source | Process environment `DP800_SQL_PASSWORD`, then `SQLCMDPASSWORD`, otherwise a secure prompt |

The repository does not create, start, stop, delete, or persist the container. Never place the actual password in documentation, scripts, arguments, `.env`, or Git.

[Invoke-Bootstrap.ps1](../DEMO/bootstrap/Invoke-Bootstrap.ps1) creates and seeds a single `AdventureGearAI` database: the `catalog`/`sales`/`customer`/`security`/`ops`/`api`/`search`/`ai` domain schemas, the `ops.DemoEnvironment` marker and `ops.DemoModuleState` tracking tables, and the canonical AdventureGear ecommerce core. Modules run through the dependency-aware runner ([Invoke-DemoModule.ps1](../DEMO/scripts/Invoke-DemoModule.ps1)) against that same database, which resolves prerequisites (cumulative M01→M11) automatically. Module reset scripts remove only their own objects and leave the core intact; the only database-level reset ([Reset-AdventureGearAI.ps1](../DEMO/reset/Reset-AdventureGearAI.ps1)) is hard-scoped to the literal `AdventureGearAI`. Legacy per-module `DP800_Mxx` databases are never created or dropped automatically; they are only reported as manual cleanup candidates. Unsupported or preview local features are detected and reported rather than assumed: the local path does not promise Azure external-model, DiskANN, managed-identity, or REST behavior.

## Toggle-safe delivery patterns

- **AI only:** disable gallery, MI, both VMs, PostgreSQL, and operations. No `admin_password`.
- **AI resources without SQL bootstrap:** AI-only plus `enable_data_plane=false`.
- **Operations base only:** enable operations while gallery remains disabled. No maintenance chain and no `admin_password`.
- **All main features disabled:** disable all eight main toggles. The common resource group/provider helper objects remain, but no password is required.
- **Full gallery:** defaults. Requires secure runtime password input and a deliberate cost/timing review.

Use toggle-based plans rather than routine `-target` plans. Exact commands are in [TERRAFORM/README.md](../TERRAFORM/README.md#safer-scoped-plans).

## Validation and delivery gate

Completed:

- Terraform initialization without a backend;
- recursive formatting check;
- `terraform validate`;
- AI implementation/static script checks;
- full default plan validation with a placeholder-only runtime password;
- password-free scoped plan validation;
- documentation path/link and Git hygiene checks.

Not completed:

- Azure `terraform apply`;
- live model deployment/quota confirmation;
- execution of all 104 embedding operations and AI smoke queries in Azure;
- live Database Watcher/Automation behavior;
- Azure `terraform destroy`.

Therefore the environment is **not yet end-to-end delivery-ready**. Before delivery, perform and record a real plan/apply/data-plane verification/output review/destroy cycle in the target subscription, then recheck model lifecycle, region, and quota.

For Database Watcher's current preview status, see [Monitor Azure SQL workloads with database watcher](https://learn.microsoft.com/azure/azure-sql/database-watcher-overview?view=azuresql).
