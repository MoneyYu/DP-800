# DP-800 Course Reference Repo — Execution Plan

**Date:** 2026-08-03
**Source plan:** session `738e5108-4c57-49f0-bded-1326be73fbb3/plan.md`
**Design spec:** `docs/superpowers/specs/2026-08-03-dp-800-course-prep-design.md`

---

## Phase 0 — Git/GitHub Baseline (this agent)

- [x] Read session plan
- [x] Create `docs/superpowers/specs/2026-08-03-dp-800-course-prep-design.md`
- [x] Create `docs/superpowers/plans/2026-08-03-dp-800-course-prep.md` (this file)
- [x] Create `.github/copilot-instructions.md`
- [x] Create GitHub issue: "Prepare DP-800 course reference repository" with scope & acceptance criteria
- [x] Add issue comment: planning complete, confirmed DP-800 identity, next steps
- [x] Verify no secrets, no conflicts with plan

---

## Phase 1 — Official Content Research

**Prerequisite:** None
**Output artifacts:** `docs/url-ledger.md`

- [ ] Fetch Learn course page: `https://learn.microsoft.com/training/courses/dp-800t00`
- [ ] Fetch all three learning path URLs and verify canonical redirects for `aka.ms/develop-ai-enabled-database-solutions`
- [ ] Fetch 11 module pages; record canonical URL, title, locale availability (EN, zh-cn, zh-tw)
- [ ] Fetch credential/study guide: SQL AI Developer Associate
- [ ] Verify `aka.ms/SQLAIDevLabs` and GitHub Pages lab URLs → record final destination
- [ ] Fetch official lab page for each of 11 labs; record URL, `main.zip` link
- [ ] Cross-reference 2026-03 DP-800 PPT speaker notes → build module/lab/demo/knowledge-check mapping
- [ ] Search Microsoft Learn and official YouTube channels for DP-800 module videos; verify channel ownership
- [ ] Build `docs/url-ledger.md`:
  - Columns: `url`, `status_code`, `final_url`, `title`, `locale`, `official_channel`, `module`
  - Mark any generic hub, redirect, or non-official URL as excluded
- [ ] Verify no placeholder or unverified URL remains in ledger

**Validation:** All URLs return 200; no generic hub pages; all videos on official Microsoft channels.

---

## Phase 2 — Attendee README Rewrite

**Prerequisite:** Phase 1 complete
**Target file:** `README.md`

- [ ] Preserve HackMD front matter, admonition syntax, and markmap fenced block format
- [ ] Replace DP-300 course intro with DP-800T00-A: title, 3-day positioning, certification
- [ ] Add session metadata section with placeholders: `<YYYYMMDD>`, `<ESI-COURSE-ID>`, `<SURVEY-URL>`, `<SKILLABLE-KEY>`
- [ ] Add ESI/Skillable access instructions (generic, no session-specific values)
- [ ] List 11 labs with: official exercise title, published lab page URL (from ledger), `main.zip` link
- [ ] Add `Links` section organized by three learning paths → 11 modules; only verified official Microsoft URLs
- [ ] Add `Videos` section organized by module; only verified official Microsoft channel videos
- [ ] Add DP-800 markmap at end, consistent with Links taxonomy (three learning paths, 11 modules)
- [ ] Remove all DP-300 content, AZ-204 references, old session metadata, Terraform content, model selection, internal deployment info

**Validation commands:**
```powershell
# Check markmap fence
Select-String -Path README.md -Pattern '```markmap' -SimpleMatch
# Check no DP-300 references remain
Select-String -Path README.md -Pattern 'DP-300|dp-300|DP300' -SimpleMatch
# Check no secrets
Select-String -Path README.md -Pattern 'password|Password|PASSWORD' -SimpleMatch
```

---

## Phase 3 — DEMO Rebuild

**Prerequisite:** Phase 1 complete
**Target directory:** `DEMO/`

- [ ] Remove all existing `DEMO/` contents (DP-300/AZ-204 SQL, backup files, admin demos)
- [ ] Create top-level `DEMO/README.md`: overview, prerequisites (Docker SQL 2025 or Azure SQL), env var setup
- [ ] Create `DEMO/.env.example`:
  ```
  DP800_SQL_PASSWORD=
  SQLCMDPASSWORD=
  AZURE_SQL_SERVER=
  AZURE_SQL_DATABASE=
  ```
- [ ] Create one directory per module `DEMO/01-database-objects/` through `DEMO/11-rag-solutions/` each containing:
  - `README.md`: goal, prerequisites, local/Azure path notes, execution order, expected results
  - `common/00-schema.sql`: shared schema and sample data (fictional, no real PII)
  - `local/01-*.sql` or `.ps1`: Docker SQL Server 2025 scripts; password via `$env:DP800_SQL_PASSWORD` only
  - `azure/01-*.sql` or `.ps1`: Azure SQL / MI / Fabric scripts
  - `reset/reset.sql` or `reset.ps1`: drops and rebuilds module objects; safe to re-run; never drops non-DP-800 databases
- [ ] Module-specific requirements:
  - Modules 1–3 (DB objects, programmability, T-SQL): both local and azure paths
  - Module 4 (AI-assisted SQL): GitHub Copilot workflow demo; both paths
  - Module 5 (Security): SQL Auth + Entra ID + Managed Identity; no hardcoded object IDs
  - Module 6 (Performance): Query Store, execution plans, blocking/deadlock demos
  - Module 7 (CI/CD): SQL database project, SqlPackage commands
  - Module 8 (Azure integration): Data API Builder local + Azure; both paths
  - Modules 9–11 (AI): external model/credential, embeddings, vector index, vector/hybrid search, RAG stored procedure; Azure path required; local path where SQL Server 2025 supports it
- [ ] Create `DEMO/bootstrap/bootstrap.ps1`: creates all DP-800 demo databases from scratch; idempotent; password from env var
- [ ] Remove `PPT/DP-300/` directory
- [ ] Remove `NOTE.md`

**Validation commands:**
```powershell
# No secrets in DEMO
Select-String -Path DEMO -Pattern 'password\s*=' -Recurse -SimpleMatch -CaseSensitive
# .env not tracked
git ls-files DEMO/.env
# All reset scripts present
Get-ChildItem DEMO -Recurse -Filter 'reset*' | Measure-Object
```

---

## Phase 4 — Terraform Modernization

**Prerequisite:** Official AzureRM/AzAPI migration guides read
**Target directory:** `TERRAFORM/`

- [ ] Read current `TERRAFORM/` structure to inventory all `.tf` files
- [ ] Read AzureRM provider changelog for breaking changes since `~> 3.0` to current
- [ ] Read AzAPI provider changelog since `~> 2.0`
- [ ] Upgrade `required_version` in `versions.tf` to `>= 1.9`
- [ ] Upgrade provider constraints: `azurerm ~> 4.0`, `azapi ~> 2.0` (verify latest minor)
- [ ] Rename all `dp300` resource names, labels, and tags to `dp800`
- [ ] Fix variable `user_passowrd` → `admin_password`; add `sensitive = true`; remove default value
- [ ] Replace hardcoded Entra administrator object ID with `var.admin_object_id` or `data.azurerm_client_config.current.object_id`
- [ ] Add `variables.tf` entries with validation blocks:
  - `group_postfix` (string, 1–8 chars, alphanumeric)
  - `location` (default `japaneast`)
  - `ai_location` (default `""`, used only when Japan East lacks AI model support)
  - `admin_password` (sensitive, no default)
  - `admin_object_id` (optional, falls back to current client)
  - `enable_core_sql_ai` (bool, default `true`)
  - `enable_azure_sql_gallery` (bool, default `true`)
  - `enable_sql_managed_instance` (bool, default `true`)
  - `enable_sql_vm_2019` (bool, default `true`)
  - `enable_sql_vm_2022` (bool, default `true`)
  - `enable_postgresql_flexible` (bool, default `true`)
  - `enable_operations` (bool, default `true`)
- [ ] Create module directories: `modules/core-sql-ai/`, `modules/azure-sql-gallery/`, `modules/sql-managed-instance/`, `modules/sql-vm-2019/`, `modules/sql-vm-2022/`, `modules/postgresql-flexible/`, `modules/operations/`
- [ ] Move existing Azure SQL resources into `modules/azure-sql-gallery/`
- [ ] Move SQL MI resources into `modules/sql-managed-instance/`
- [ ] Move SQL VM 2019/2022 resources into respective modules
- [ ] Migrate `azurerm_postgresql_server` (Single Server) → `azurerm_postgresql_flexible_server` in `modules/postgresql-flexible/`
- [ ] Move Database Watcher, Key Vault, Automation into `modules/operations/`; update Key Vault to RBAC mode
- [ ] Create `modules/core-sql-ai/` skeleton for DP-800 Azure SQL + OpenAI/Foundry (full implementation in Phase 5)
- [ ] Fix SQL auditing: RBAC/identity primary; access-key path behind `enable_storage_key_auditing` toggle; key never in outputs
- [ ] Update `OUTPUT.tf`: resource names, FQDNs, endpoints, demo instructions only — no secrets
- [ ] Add `TERRAFORM/README.md` (see Phase 6)
- [ ] Run validation:

```powershell
cd TERRAFORM
terraform fmt -recursive
terraform init -backend=false -upgrade
terraform validate
# Default all-on plan
terraform plan -var="admin_password=DummyForValidation1!" -out=tfplan-default
# Each toggle off individually
terraform plan -var="admin_password=DummyForValidation1!" -var="enable_sql_managed_instance=false" -out=tfplan-no-mi
terraform plan -var="admin_password=DummyForValidation1!" -var="enable_sql_vm_2019=false" -var="enable_sql_vm_2022=false" -out=tfplan-no-vm
Remove-Item tfplan-*
```

---

## Phase 5 — DP-800 AI/RAG Terraform Module

**Prerequisite:** Phase 4 complete; model lifecycle and Japan East availability verified
**Target:** `TERRAFORM/modules/core-sql-ai/`

- [ ] Verify current GA embedding model available in Japan East (or document `ai_location` override)
- [ ] Verify current GA chat/completion model available in Japan East
- [ ] Create `azurerm_cognitive_account` (Azure OpenAI) or Foundry project resource
- [ ] Create model deployments: embedding model + chat/completion model
- [ ] Create DP-800 Azure SQL logical server with Entra admin and SQL auth
- [ ] Create DP-800 Azure SQL database (General Purpose, appropriate SKU for vector/AI demos)
- [ ] Create `azurerm_user_assigned_identity` for Azure SQL → Azure OpenAI calls
- [ ] Assign RBAC roles: `Cognitive Services OpenAI User` to managed identity on OpenAI resource
- [ ] Create `TERRAFORM/data-plane/` PowerShell scripts:
  - `01-create-schema.ps1`: creates sample schema and data
  - `02-create-external-model.ps1`: creates external model/credential in Azure SQL
  - `03-generate-embeddings.ps1`: generates embeddings for sample data
  - `04-create-vector-index.ps1`: creates vector index
  - `05-vector-search.ps1`: executes vector/hybrid search; verifies results
  - `06-rag-procedure.ps1`: creates and smoke-tests RAG stored procedure
  - All scripts: password via env var only; explicit timeout/retry with terminal failure on error
- [ ] Update `OUTPUT.tf`: AI resource names, endpoints, demo instructions

**Validation commands:**
```powershell
cd TERRAFORM
terraform fmt -recursive
terraform validate
# Plan with core enabled, expensive modules off
terraform plan -var="admin_password=DummyForValidation1!" -var="enable_sql_managed_instance=false" -var="enable_sql_vm_2019=false" -var="enable_sql_vm_2022=false" -out=tfplan-core
Remove-Item tfplan-core
```

---

## Phase 6 — Terraform Documentation & Sample Data

**Prerequisite:** Phase 4 & 5 complete

- [ ] Create `TERRAFORM/README.md`:
  - **⚠️ HIGH COST WARNING** at top: SQL MI (~$400+/month), SQL VMs (~$100+/month each) — deploy selectively
  - Prerequisites: Terraform >= 1.9, Azure CLI logged in, PowerShell 7
  - Sensitive variables: `admin_password` (required), `admin_object_id` (optional)
  - All feature toggles table: variable name, default, resource group, estimated cost, deploy time
  - Japan East policy + `ai_location` override explanation
  - Commands: `terraform init`, `terraform plan`, `terraform apply`, selective apply per module, re-run data plane, `terraform destroy`
  - Demo auth modes per module: SQL Auth, Entra ID, Managed Identity
  - Cost and quota notes per module
- [ ] Create `docs/demo-environment.md`: resource topology, models, auth modes, module mapping, known limitations
- [ ] Create `docs/local-sql-server.md`:
  - Container facts (name, host, port, login, SQL version)
  - Password env var setup (instructions only, no actual password)
  - Bootstrap/reset flow per session
  - Local vs Azure feature difference table
  - Explicit statement: repo does not create/stop/delete/persist Docker container
- [ ] Create fictional sample data files in `TERRAFORM/data-plane/sample-data/` (CSV or SQL)
- [ ] Update `.gitignore`:
  - Add `.env`, `*.env`, `terraform.tfstate`, `terraform.tfstate.*`, `.terraform/`, `*.tfvars` (except `.tfvars.example`)
- [ ] Update `.gitattributes`:
  - Add LFS rules for: `*.bak`, `*.bacpac`, `*.tar`, `*.pdf`, `*.pptx`, `*.png`, `*.jpg`, `*.jpeg`

---

## Phase 7 — Trainer Teaching Guide

**Prerequisite:** Phase 1, 3, 4, 5 complete
**Target file:** `docs/teaching-guide.md`
**Language:** 繁體中文; technical names and URLs in English

- [ ] Create 3-day agenda with time allocation (learning paths as day boundaries)
- [ ] Create three learning path / 11 module / 11 lab cross-reference table
- [ ] For each of the 11 modules, add section containing:
  - Learning objectives
  - Key lecture points
  - Demo reference (module directory in `DEMO/`)
  - Lab reference (official lab URL)
  - Speaker notes highlights
  - Knowledge check questions
  - Common student questions / pitfalls
  - Important links (from verified ledger)
- [ ] Add cross-module concepts section: SQL platform selection, security, performance, CI/CD, embeddings, vector search, RAG
- [ ] Add pre-session checklist:
  - Azure quota check (OpenAI, SQL, VM)
  - Model availability in Japan East
  - SQL Server 2025 container running: `docker ps --filter name=mssql2025`
  - Azure CLI login: `az account show`
  - Terraform init: `terraform init -backend=false`
  - Skillable key distribution
  - Bootstrap demo databases: `DEMO/bootstrap/bootstrap.ps1`
- [ ] Add live demo failure recovery: switch to Terraform backup environment steps
- [ ] Add local vs Azure difference summary per relevant module

---

## Phase 8 — Static Validation

**Prerequisite:** Phases 2–7 complete

- [ ] Run link ledger checker against `docs/url-ledger.md`; fix redirects, generic hubs, locale fallbacks, non-official videos
- [ ] `terraform fmt -recursive` (zero diff required)
- [ ] `terraform init -backend=false -upgrade`
- [ ] `terraform validate` (must pass)
- [ ] `terraform plan` for each feature toggle individually (all must succeed)
- [ ] `terraform plan` with all toggles default (must succeed)
- [ ] PowerShell AST parse all scripts in `DEMO/` and `TERRAFORM/data-plane/`
- [ ] SQL syntax check: dry-run or parser on all `.sql` files
- [ ] Secret scan:
  ```powershell
  # No actual passwords
  Select-String -Path . -Pattern 'DP800_SQL_PASSWORD\s*=' -Recurse -Include *.ps1,*.sql,*.tf,*.md | Where-Object { $_ -notmatch '\.env\.example|placeholder|<password>' }
  # No Terraform sensitive outputs
  Select-String -Path TERRAFORM -Pattern 'sensitive\s*=\s*false' -Recurse
  # No personal object IDs (36-char GUID pattern in .tf files)
  Select-String -Path TERRAFORM -Pattern '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -Recurse -Include *.tf
  ```
- [ ] Check README markmap fence closes correctly
- [ ] Check internal links in README resolve to real files
- [ ] Verify `.gitattributes` covers all binary extensions

---

## Phase 9 — Local Docker SQL Server 2025 Validation

**Prerequisite:** Phase 8 complete
**Environment:** `mssql2025` container at `127.0.0.1:1433`

- [ ] Connect via `$env:DP800_SQL_PASSWORD`; verify connection succeeds without exposing password in command line
- [ ] Execute bootstrap from clean state; verify all DP-800 demo databases created
- [ ] Execute modules 1–8 `local/` scripts in order; verify expected objects and query results
- [ ] Execute modules 9–11 `local/` scripts where SQL Server 2025 supports the feature; document gaps
- [ ] Execute each module's `reset/` script; verify clean state without affecting other databases
- [ ] Re-run bootstrap + all demos; confirm no dependency on prior state

---

## Phase 10 — Azure End-to-End Validation (7 groups)

**Prerequisite:** Phase 9 complete
**Each group uses unique `group_postfix`**

- [ ] Group 1: DP-800 core Azure SQL + OpenAI/Foundry + embeddings/vector/RAG
  - `terraform apply -target=module.core_sql_ai`
  - Run all `TERRAFORM/data-plane/` scripts
  - Verify query results for vector search and RAG
  - `terraform destroy -target=module.core_sql_ai`
- [ ] Group 2: Azure SQL single/elastic pool/Hyperscale gallery
  - Apply, verify connectivity and SKU, destroy
- [ ] Group 3: SQL Managed Instance — **⚠️ ~4 hour deploy, high cost**
  - Apply, verify SQL MI endpoint and auth, destroy
- [ ] Group 4: SQL Server 2019 VM
  - Apply, verify SQL IaaS extension, run sample query, destroy
- [ ] Group 5: SQL Server 2022 VM
  - Apply, verify SQL IaaS extension, run sample query, destroy
- [ ] Group 6: PostgreSQL Flexible Server
  - Apply, verify connectivity, run sample query, destroy
- [ ] Group 7: Database Watcher, Key Vault, Automation
  - Apply, verify watcher target, Key Vault RBAC, Automation credential, destroy
- [ ] Full default deploy (all toggles on, unique postfix)
  - Verify no naming/network/quota/dependency conflicts
  - Destroy all
- [ ] Run `azure/` demo scripts per module; document local vs Azure differences in teaching guide

**Per-deployment logging (add to GitHub issue comments):**
- Azure cost estimate
- Actual deploy time
- Japan East availability issues
- Quota warnings
- Soft-delete name reservation issues

---

## Phase 11 — Git Close-Out

**Prerequisite:** Phases 1–10 complete

- [ ] Stage and commit in logical groups (Conventional Commits):
  - `docs: DP-800 research and URL ledger`
  - `docs(readme): rewrite attendee README for DP-800`
  - `demo: rebuild DEMO for DP-800 11-module structure`
  - `chore(terraform): modernize root, variables, toggles, naming`
  - `feat(terraform): add DP-800 AI/RAG core module`
  - `docs(terraform): add TERRAFORM/README and demo-environment docs`
  - `docs(trainer): add teaching guide and local SQL Server docs`
  - `chore: update .gitignore and .gitattributes`
- [ ] Each commit message includes issue closing reference: `Closes #<issue-number>`
- [ ] Each commit includes trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
- [ ] Remove any temp files
- [ ] Verify working tree: `git status` shows only expected tracked changes
- [ ] Verify no binary blobs without LFS pointer
- [ ] Update GitHub issue with final validation results summary; close issue
