# DP-800 Course Reference Repo — Approved Design Decisions

**Status:** Approved
**Date:** 2026-08-03
**Course:** DP-800T00-A: Develop AI-enabled database solutions (3 days)
**Certification:** Microsoft Certified: SQL AI Developer Associate
**Official lab repo:** `MicrosoftLearning/mslearn-sql-developer`

---

## 1. Repository Purpose & Scope

This repo is the **trainer reference repository** for DP-800T00-A, converted from DP-300. It serves:

- Attendee-facing README (course orientation, labs, links)
- Instructor demo scripts (11-module coverage)
- Repeatable Terraform backup environment
- Trainer teaching guide (zh-TW)

It does **not** own Docker container lifecycle, PPT authoring, or exam content.

---

## 2. Course Identity

| Field | Value |
|---|---|
| Course code | DP-800T00-A |
| Duration | 3 days |
| Labs | 11 official exercises |
| Learning paths | Design and Develop Database Solutions (4 modules) · Secure, Optimize, and Deploy Database Solutions (4 modules) · Implement AI Capabilities in Database Solutions (3 modules) |

### 11 Labs

1. Create database objects
2. Implement programmability objects
3. Write advanced T-SQL code
4. Design and implement SQL solutions using AI-assisted tools
5. Implement security and compliance
6. Optimize database performance
7. Implement CI/CD for SQL database projects
8. Integrate SQL solutions with Azure services
9. Generate and maintain embeddings with SQL
10. Implement intelligent search with SQL
11. Implement RAG solutions with SQL

---

## 3. Content Boundary: Attendee README vs Trainer Docs

| Content | Attendee README | Trainer docs (`docs/`) |
|---|---|---|
| Course intro, 3-day positioning | ✅ | ❌ |
| Session metadata placeholders | ✅ | ❌ |
| Lab list with official URLs | ✅ | ❌ |
| Verified links & videos (by module) | ✅ | ❌ |
| DP-800 markmap | ✅ | ❌ |
| Terraform setup, feature toggles | ❌ | ✅ |
| Model selection, region overrides | ❌ | ✅ |
| Internal deployment steps | ❌ | ✅ |
| Teaching guide, speaker notes | ❌ | ✅ |

---

## 4. Legacy Content Disposition

| Item | Decision |
|---|---|
| `DEMO/` (DP-300/AZ-204 SQL, backups) | Remove and replace with DP-800 structure |
| `PPT/DP-300/` | Remove |
| `NOTE.md` (AZ-204 content) | Remove |
| `TERRAFORM/` database resources | **Keep all** — upgrade, do not delete |
| `PPT/DP-800/` | Keep |

---

## 5. Terraform Architecture

### Design: DP-800 core + switchable legacy database gallery

**Root module** manages: providers, shared variables, naming, resource group, feature toggles, outputs.

**Feature modules** (each with `enable_*` toggle, default `true`):

| Module | Contents |
|---|---|
| `core-sql-ai` | DP-800 Azure SQL, Foundry/Azure OpenAI, embeddings, vector search, RAG |
| `azure-sql-gallery` | Single DB, elastic pool, Hyperscale, auditing |
| `sql-managed-instance` | SQL MI (high cost — prominently documented) |
| `sql-vm-2019` | SQL Server 2019 VM |
| `sql-vm-2022` | SQL Server 2022 VM |
| `postgresql-flexible` | PostgreSQL Flexible Server (replaces deprecated Single Server) |
| `operations` | Database Watcher, Key Vault, Automation |

**Toggle contract:** disabling any module must allow safe evaluation of outputs and dependent resources.

### Region Policy

- Default: `Japan East` for all resources.
- AI model deployments not available in Japan East: add narrow `ai_location` or per-model override.
- Document Japan East availability and quota requirements explicitly.

### Variable & Secrets Policy

- `admin_password`: sensitive input, no default value (fixes `user_passowrd` typo).
- Entra administrator object ID: obtained from input variable or `azurerm_client_config`/Entra lookup — never hardcoded.
- SQL auditing: RBAC/identity-first; access-key path isolated behind explicit toggle, key never output.
- No secrets in `OUTPUT.tf`; only resource names, FQDNs, endpoints, demo instructions.

### PostgreSQL

- Migrate from deprecated `azurerm_postgresql_server` (Single Server) to `azurerm_postgresql_flexible_server`.
- Validate against current AzureRM provider docs before implementation.

### Database Watcher

- Verify GA API availability before implementation; if still preview, pin API version and document explicitly.

### Key Vault

- RBAC-first mode (`enable_rbac_authorization = true`).
- Optional demo toggle for access-policy comparison.

---

## 6. Demo Structure

### Dual-path principle

Every applicable module provides both:
- `local/` — connects to `127.0.0.1:1433`, login `sa`, password via `$env:DP800_SQL_PASSWORD` or `$env:SQLCMDPASSWORD` or interactive secure prompt only.
- `azure/` — Azure SQL / Managed Instance / Fabric SQL scripts.
- `common/` — shared schema, sample data, platform-neutral queries.
- `reset/` — removes and rebuilds that module's demo objects.
- `README.md` — goals, prerequisites, local/Azure differences, execution order, expected results.

Azure-only features are explicitly marked with fallback or difference notes for local path.

### Authentication modes demonstrated

- SQL Authentication
- Microsoft Entra ID (administrator + user)
- Managed Identity

No hardcoded passwords, personal object IDs, or secrets in any demo script.

### Local environment facts

| Property | Value |
|---|---|
| Container image | `mcr.microsoft.com/mssql/server:2025-latest` |
| Container name | `mssql2025` |
| SQL version | 17.0.4065.4 |
| Host | `127.0.0.1:1433` |
| Login | `sa` |
| Password source | `$env:DP800_SQL_PASSWORD` / `$env:SQLCMDPASSWORD` / interactive prompt |

### Container lifecycle

The repo does **not** create, stop, delete, or persist the Docker container or its volumes.
Each course session runs a bootstrap/reset from a clean demo database state.
Reset scripts assume the database may not exist or can be safely rebuilt; they never drop databases outside the DP-800 naming convention.

### `.env.example`

Provided without secrets. Actual `.env` is git-ignored.

---

## 7. Security Constraints (non-negotiable)

1. No secrets, passwords, tokens, or personal object IDs committed to Git.
2. `admin_password` has no Terraform default value.
3. Entra object IDs never hardcoded.
4. Storage access key paths for auditing isolated behind toggle; key never output.
5. Local SA password never appears in README, scripts, command history, or any persisted artifact.
6. `.env` in `.gitignore`; `.env.example` contains only variable names and placeholders.
7. Pre-commit scan must confirm no actual secrets in repo.

---

## 8. gitattributes & gitignore Policy

`.gitattributes` must declare LFS for: `.bak`, `.bacpac`, `.tar`, `.pdf`, `.pptx`, `.png`, `.jpg`
`.gitignore` must exclude: `.env`, `*.tfvars` containing secrets, `terraform.tfstate*`, `.terraform/`

---

## 9. Session Metadata Placeholders

Session-specific fields use explicit placeholders (not TBD/TODO):

| Field | Placeholder |
|---|---|
| Session date | `<YYYYMMDD>` |
| ESI Course ID | `<ESI-COURSE-ID>` |
| Survey URL | `<SURVEY-URL>` |
| Skillable training key | `<SKILLABLE-KEY>` |

---

## 10. Model Lifecycle Rule

AI model deployments must use currently available GA models at time of implementation.
Japan East availability and quota must be verified.
Region override (`ai_location`) required only when Japan East lacks support.
Model selection must be re-verified before each course delivery.

---

## 11. Risks & Constraints

| Risk | Mitigation |
|---|---|
| `azurerm_postgresql_server` deprecated | Migrate to Flexible Server; verify schema from official docs |
| Context7 unavailable during planning | Use HashiCorp official migration guides at implementation time |
| SQL MI / VM high cost & long deploy | Prominent warning in `TERRAFORM/README.md`; deploy selectively |
| AI model region/preview/GA status changes | Re-verify at implementation and before each course delivery |
| Japan East capacity constraints | Document; use `ai_location` override as needed |
