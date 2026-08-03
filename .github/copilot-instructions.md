# GitHub Copilot Instructions — DP-800 Course Reference Repository

This repository is the **trainer reference repository** for **DP-800T00-A: Develop AI-enabled database solutions** (3 days, 11 labs, Microsoft Certified: SQL AI Developer Associate).

---

## Content Boundaries

### Attendee README (`README.md`)
Contains **only**:
- Course title, 3-day positioning, certification info
- Session metadata placeholders (`<YYYYMMDD>`, `<ESI-COURSE-ID>`, `<SURVEY-URL>`, `<SKILLABLE-KEY>`)
- Official lab list (11 labs) with published URLs and `main.zip` links
- Verified links organized by three learning paths / 11 modules
- Verified videos from official Microsoft channels, organized by module
- DP-800 markmap consistent with the Links taxonomy

**Does NOT contain**: Terraform setup, feature toggles, model selection, internal deployment, trainer prep, session-specific metadata.

### Trainer Docs (`docs/`)
Contains:
- `teaching-guide.md` — 繁體中文 trainer guide; technical names and URLs in English
- `demo-environment.md` — resource topology, models, auth modes, module mapping
- `local-sql-server.md` — Docker SQL Server 2025 setup and local/Azure feature differences
- `url-ledger.md` — verified URL/video ledger for all course links
- `superpowers/` — planning specs and execution plans

---

## Terraform Rules

### Keep all database resource groups
All existing database environments in `TERRAFORM/` must be preserved and kept deployable. Do not delete any resource group.

### Feature toggles — all default `true`
Every module has an `enable_*` boolean variable defaulting to `true`. Disabling any module must allow safe evaluation of all outputs and dependent resources.

**Toggle variables (all `default = true`):**
- `enable_core_sql_ai`
- `enable_azure_sql_gallery`
- `enable_sql_managed_instance`
- `enable_sql_vm_2019`
- `enable_sql_vm_2022`
- `enable_postgresql_flexible`
- `enable_operations`

### Default region: Japan East
All resources default to `japaneast`. Only add a narrow `ai_location` or per-model override when Japan East does not support a specific AI model deployment. Document the override reason.

### Secrets policy
- `admin_password`: sensitive input variable, **no default value**
- Entra administrator object ID: from `var.admin_object_id` or `azurerm_client_config`; **never hardcoded**
- SQL auditing: RBAC/identity primary; access-key path behind `enable_storage_key_auditing` toggle only; key **never** in outputs
- `OUTPUT.tf`: resource names, FQDNs, endpoints, demo instructions **only** — no secrets, no passwords, no access keys

### PostgreSQL
Use `azurerm_postgresql_flexible_server`. The deprecated `azurerm_postgresql_server` (Single Server) must not be used.

### Database Watcher
Verify GA API availability before use. If still preview, pin API version and document explicitly.

---

## DP-800 Local / Azure Dual Path

Every applicable demo module provides:
- `local/` — SQL Server 2025 at `127.0.0.1:1433`, login `sa`
- `azure/` — Azure SQL / Managed Instance / Fabric SQL
- `common/` — shared schema, sample data
- `reset/` — clean teardown and rebuild; safe to re-run; never drops non-DP-800 databases

### Local environment
| Property | Value |
|---|---|
| Image | `mcr.microsoft.com/mssql/server:2025-latest` |
| Container | `mssql2025` |
| Host:port | `127.0.0.1:1433` |
| Login | `sa` |
| Password source | `$env:DP800_SQL_PASSWORD` or `$env:SQLCMDPASSWORD` or interactive secure prompt |

The repo does **not** create, stop, delete, or persist the Docker container. Bootstrap/reset assumes database may not exist or can be safely rebuilt.

### Azure-only features
Mark clearly in demo `README.md` with expected behavior or closest local alternative.

---

## Secrets Must Never Be Committed

1. No passwords, tokens, API keys, connection strings with credentials, or personal object IDs in any file committed to Git.
2. `admin_password` has no Terraform default.
3. Local SA password: never in README, scripts, `.env`, or command history — only via env var or interactive prompt.
4. `.env` must be in `.gitignore`; only `.env.example` (no values) may be committed.
5. Pre-commit: scan for actual secrets before every commit.

---

## Verification Commands

```powershell
# Terraform format check
cd TERRAFORM; terraform fmt -recursive -check

# Terraform init (no backend)
terraform init -backend=false -upgrade

# Terraform validate
terraform validate

# Default all-toggles-on plan (dummy password for validation only)
terraform plan -var="admin_password=DummyForValidation1!"

# Secret scan — no passwords in .tf files
Select-String -Path TERRAFORM -Pattern 'password\s*=\s*"[^"$<{]' -Recurse -Include *.tf

# Secret scan — no hardcoded GUIDs in .tf files
Select-String -Path TERRAFORM -Pattern '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -Recurse -Include *.tf

# No DP-300 references in README
Select-String -Path README.md -Pattern 'DP-300|dp-300|DP300' -SimpleMatch

# Local SQL Server running
docker ps --filter name=mssql2025 --format "{{.Status}}"

# Azure CLI logged in
az account show --query "{name:name, id:id}" -o table

# PowerShell AST parse all DEMO scripts
Get-ChildItem DEMO -Recurse -Include *.ps1 | ForEach-Object {
  $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
  if ($errors) { Write-Error "Parse error in $($_.Name)" }
}
```

---

## Model Lifecycle Rules

1. AI model deployments must use **currently available GA models** at time of implementation.
2. Verify Japan East availability and quota before deploying.
3. Use `ai_location` override **only** when Japan East lacks support for a specific model.
4. **Re-verify model availability before each course delivery** — models retire without notice.
5. Document in `docs/demo-environment.md`: model name, version, deployment SKU, region, verification date.

---

## Session Metadata Placeholders

Use explicit placeholders (never TBD/TODO):

| Field | Placeholder |
|---|---|
| Session date | `<YYYYMMDD>` |
| ESI Course ID | `<ESI-COURSE-ID>` |
| Survey URL | `<SURVEY-URL>` |
| Skillable training key | `<SKILLABLE-KEY>` |

---

## What This Repo Does NOT Do

- Does not own DP-300 content (all DP-300 DEMO, PPT/DP-300, NOTE.md removed)
- Does not create, stop, or delete Docker containers or volumes
- Does not commit secrets, passwords, or personal object IDs
- Does not publish attendee session-specific data
- Does not modify existing `.gitignore` entries protecting secrets
