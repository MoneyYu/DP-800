# DP-800 demo environment

This directory declares the trainer backup environment used by the DP-800 course demos. It retains the existing database gallery and adds an independent, Microsoft Entra-only Azure SQL AI stack for modules 09–11.

For the architecture and delivery status, see [docs/demo-environment.md](../docs/demo-environment.md). For the external local SQL Server 2025 path, see [DEMO/README.md](../DEMO/README.md).

## Implemented baseline

- Terraform `>= 1.9.0`.
- AzureRM provider `>= 5.0.1, < 6.0.0`; AzAPI `~> 2.11`, Random `~> 3.9`, and HTTP `~> 3.6`.
- Default Azure region: `japaneast`.
- `ai_location` is a narrow override for the Azure OpenAI account and deployments. The AI resource group and Azure SQL server/database remain in `location`.
- Every main feature toggle defaults to `true`. This is the full and potentially expensive trainer gallery, not a low-cost default.

## Prerequisites

### Control plane

1. PowerShell 7 (`pwsh`).
2. Terraform 1.9 or later.
3. Azure CLI, authenticated with `az login`.
4. An Azure subscription in which the active identity can create resource groups, register the providers in [MAIN.tf](MAIN.tf), create role assignments, and deploy the selected Azure OpenAI models.
5. Current regional capacity and subscription quota for every selected SKU/model.

Select the subscription before planning:

```powershell
az login
az account set --subscription '<subscription-id>'
$env:ARM_SUBSCRIPTION_ID = '<subscription-id>'
```

`subscription_id` can be supplied instead, but `ARM_SUBSCRIPTION_ID` or the active Azure CLI subscription keeps tenant-specific values out of files.

This configuration renames and restructures the original DP-300 resources. It is a **new DP-800 deployment**, not an in-place migration for an existing DP-300 Terraform state. Select a new backend key/workspace or remove the old local state from this directory before continuing. After verifying the selected state is new and contains no DP-300 resources, explicitly acknowledge that boundary:

```powershell
$env:TF_VAR_confirm_new_dp800_state = 'true'
```

Terraform refuses to plan without this confirmation. Do not set it merely to bypass the guard; reusing DP-300 state can replace its resource group and cascade replacement of databases, VMs, and related resources.

### AI data plane

When both `enable_core_sql_ai` and `enable_data_plane` are `true`, the machine running `terraform apply` also needs:

- PowerShell 7;
- Azure CLI logged in as the identity configured by `admin_object_id` (or the current AzureRM client identity when it is null).

No `SqlServer` PowerShell module is needed. [scripts/Deploy-AiDataPlane.ps1](scripts/Deploy-AiDataPlane.ps1) executes the SQL script with the `System.Data.SqlClient` types bundled with PowerShell 7: it strips the placeholder `:setvar` declarations, substitutes the `$(NAME)` sqlcmd variables, splits the script into `GO` batches while ignoring `GO` inside comments, string literals and bracketed identifiers, and runs every batch over one connection so session settings such as `SET XACT_ABORT ON` persist.

It obtains an Azure SQL bearer token from Azure CLI, decodes its `oid` claim, and stops if it does not match the configured SQL Microsoft Entra administrator object ID. It then waits for the SQL server managed identity and `Cognitive Services OpenAI User` assignments to propagate. Transient identity/RBAC `401` and `403` failures and documented Azure SQL transient faults, including serverless auto-pause resume, are retried. No API key is used or expected.

## Variables and feature dependencies

`group_postfix` is required and must be 1–10 lowercase letters or digits. Names are derived from `DP800-<group_postfix>`.

| Variable | Default | Implemented effect and dependency |
|---|---:|---|
| `confirm_new_dp800_state` | Required | Must be `true` after selecting a new DP-800 state/workspace; blocks accidental reuse of DP-300 state. |
| `location` | `japaneast` | Default region for the main resource group, gallery, AI SQL, and most operations resources. |
| `ai_location` | `null` | Uses `location` when null; overrides only Azure OpenAI/model placement. |
| `enable_core_sql_ai` | `true` | Independent Entra-only Azure SQL and Azure OpenAI stack. |
| `enable_data_plane` | `true` | Runs only when `enable_core_sql_ai=true`; loads the AI schema/data during apply. |
| `enable_azure_sql_gallery` | `true` | Password-based Azure SQL logical server, S1 database, Standard elastic pool/two databases, Hyperscale database, storage, auditing, and firewall rules. |
| `enable_sql_managed_instance` | `true` | Password-based 4-vCore `GP_Gen5` SQL Managed Instance and networking. |
| `enable_sql_vm_2019` | `true` | Password-based SQL Server 2019 Developer VM (`Standard_B4ms`) with premium data/log disks. |
| `enable_sql_vm_2022` | `true` | Password-based SQL Server 2022 Developer VM (`Standard_B2s`) with premium data/log disks. |
| `enable_postgresql_flexible` | `true` | Password-based PostgreSQL Flexible Server 16 (`B_Standard_B1ms`) and database. |
| `enable_operations` | `true` | Database Watcher preview, Key Vault RBAC, and Automation account. The SQL maintenance credential/runbook/schedule additionally require `enable_azure_sql_gallery=true` and `enable_azure_services_firewall_demo=true`. |
| `enable_azure_services_firewall_demo` | `true` | Adds the broad Azure-services SQL firewall rule and enables the password-based Automation maintenance chain when gallery and operations are enabled. |
| `enable_legacy_key_auth_demo` | `false` | Enables storage shared-key use only for retained auditing/SQL VM backup demonstrations. It is meaningful only with the gallery and relevant VM toggle; keep it false for the managed-identity/RBAC path. |

`admin_password` is required only when at least one password-based gallery, SQL MI, SQL VM, or PostgreSQL toggle is enabled. The deprecated `user_passowrd` alias remains only for compatibility and should not be used in new commands. AI-only and all-main-features-disabled plans do not require a password.

Meaningful combinations:

- **Full gallery:** defaults; requires `admin_password` and creates the expensive resources listed below.
- **AI only:** enable `enable_core_sql_ai` and disable gallery, MI, both VMs, PostgreSQL, and operations. Password-free.
- **AI infrastructure only:** AI-only settings plus `enable_data_plane=false`.
- **Operations only:** disable password-based features. Database Watcher, Key Vault, and the Automation account remain, but the SQL maintenance chain is omitted. Password-free.
- **All main features disabled:** disable all eight `enable_*` main toggles. Password-free; the common `DP800-<postfix>` resource group, provider data sources, and random suffix resource still remain in the plan.

## Secure password input

Never commit a real password to `.tf`, `.tfvars`, `.env`, plan, log, shell script, or Git history. Prompt for it and keep it only in the Terraform process environment:

```powershell
$securePassword = Read-Host 'DP-800 temporary admin password' -AsSecureString
$credential = [pscredential]::new('terraform', $securePassword)
$env:TF_VAR_admin_password = $credential.GetNetworkCredential().Password

try {
    terraform plan -var="group_postfix=0803"
    terraform apply -var="group_postfix=0803"
}
finally {
    Remove-Item Env:TF_VAR_admin_password -ErrorAction SilentlyContinue
    $credential = $null
    $securePassword = $null
}
```

Use a placeholder such as `<strong-password-from-secure-prompt>` in written examples only. A saved binary plan can contain sensitive values even when terminal output is redacted; protect it as a secret and delete it after use.

## Init, format, validate, plan, apply, destroy

Run from this directory:

```powershell
Set-Location TERRAFORM

terraform init -backend=false
terraform fmt -recursive
terraform fmt -check -recursive
terraform validate
pwsh -NoProfile -File .\scripts\Test-AIStack.ps1

terraform plan -var="group_postfix=0803"
terraform apply -var="group_postfix=0803"
terraform output
terraform destroy -var="group_postfix=0803"
```

Use a delivery-specific postfix. Confirm the active subscription, regions, resource names, costs, model availability, and quota in every plan before applying.

### Safer scoped plans

Prefer feature toggles over Terraform `-target`; toggle-based plans include the declared dependencies and show the complete intended scope. Example AI-only plan:

```powershell
terraform plan `
  -var="group_postfix=0803" `
  -var="enable_azure_sql_gallery=false" `
  -var="enable_sql_managed_instance=false" `
  -var="enable_sql_vm_2019=false" `
  -var="enable_sql_vm_2022=false" `
  -var="enable_postgresql_flexible=false" `
  -var="enable_operations=false"
```

Example password-free all-main-features-disabled plan:

```powershell
terraform plan `
  -var="group_postfix=0803" `
  -var="enable_core_sql_ai=false" `
  -var="enable_azure_sql_gallery=false" `
  -var="enable_sql_managed_instance=false" `
  -var="enable_sql_vm_2019=false" `
  -var="enable_sql_vm_2022=false" `
  -var="enable_postgresql_flexible=false" `
  -var="enable_operations=false" `
  -var="enable_data_plane=false"
```

Reserve `-target` for exceptional recovery after reviewing the full plan; it can hide affected resources and is not a normal deployment workflow.

## AI stack and data plane

The AI stack is deliberately independent from the password-based gallery:

- Entra-only Azure SQL Database, `GP_S_Gen5_2`, serverless minimum capacity `0.5`, system-assigned identity, and TLS 1.2.
- Azure OpenAI with `local_auth_enabled=false` and a custom subdomain.
- `text-embedding-3-small`, version `1`, 1536 dimensions.
- `gpt-5.4-mini`, version `2026-03-17`, `GlobalStandard`.
- 104 fictional product reviews (8 base rows plus 96 variants).
- Managed-identity database scoped credential and `CREATE EXTERNAL MODEL`.
- `AI_GENERATE_EMBEDDINGS`, `VECTOR(1536)`, DiskANN `CREATE VECTOR INDEX ... WITH (METRIC = 'cosine', TYPE = 'DISKANN')`, and `VECTOR_SEARCH` queries using `SELECT TOP (...) WITH APPROXIMATE`.
- Full-text indexing, `FREETEXTTABLE`, reciprocal rank fusion (RRF), and REST RAG through `sys.sp_invoke_external_rest_endpoint`.

Apply automatically runs [scripts/Deploy-AiDataPlane.ps1](scripts/Deploy-AiDataPlane.ps1) through `terraform_data.core_sql_ai_data_plane`. To provision infrastructure without executing SQL, set `enable_data_plane=false`. To intentionally rerun the completed data plane after infrastructure exists:

```powershell
terraform apply `
  -replace='terraform_data.core_sql_ai_data_plane[0]' `
  -var="group_postfix=0803"
```

Before every delivery, recheck the exact model versions, deployment type, Japan East (or `ai_location`) availability, and subscription quota against the current [Foundry model catalog and region tables](https://learn.microsoft.com/azure/ai-foundry/openai/concepts/models). A successful historical plan does not reserve capacity.

## Cost and timing warning

The default plan includes continuously billed and/or high-cost resources: SQL Managed Instance, two SQL VMs plus premium disks and PAYG SQL VM management, Hyperscale, the Standard elastic pool, PostgreSQL, Azure OpenAI deployments, Database Watcher preview, Key Vault, and Automation.

SQL Managed Instance commonly takes much longer than the other resources to provision or delete; allow substantial time and do not interrupt Terraform merely because MI remains in a creating/deleting state. Review current Azure pricing and quota before apply, and destroy the course environment promptly after validation.

## Validation status

Static formatting, Terraform validation, implementation checks, the full default plan, and password-free scoped plans are complete. Azure end-to-end testing is **not** complete. A real `terraform apply`, AI data-plane smoke test, output review, and `terraform destroy` must all succeed in the target subscription before this environment is considered delivery-ready.
