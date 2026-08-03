# DP-800 README Links and Mind Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty/generic DP-800 reference section with module-specific official documentation and rebuild the markmap as a concise DP-800 course-outline map modeled on MoneyYu/AI-901.

**Architecture:** `README.md` remains attendee-facing. Its `Links` section follows the original DP-300 pattern by grouping authoritative references under M01-M11; its markmap follows AI-901's `module -> curriculum topic -> core concepts` hierarchy. `docs/link-ledger.txt` is the single validation inventory for every HTTP link used by the README.

**Tech Stack:** Markdown, HackMD markmap, Microsoft Learn, official GitHub documentation, Python link checker.

## Global Constraints

- Use only current official Microsoft Learn/product documentation and official Microsoft/GitHub repositories.
- Every reference must directly support a DP-800 module learning objective.
- Do not include Terraform, trainer demo implementation, generic product hubs, blogs, Q&A, or third-party links in the attendee reference section.
- The mind map represents the course outline; it is not a resource directory or architecture diagram.
- Preserve the four delivery placeholders and all existing Course, Lab, Exam, and Contact sections.

---

### Task 1: Establish README regression checks

**Files:**
- Modify: `README.md`
- Modify: `docs/link-ledger.txt`

**Interfaces:**
- Consumes: Current DP-800 module order from `docs/course-research.md`.
- Produces: Repeatable structural assertions used by Tasks 2-4.

- [ ] **Step 1: Run the failing structural check**

```powershell
$readme = Get-Content .\README.md -Raw
if ($readme -notmatch '## Links\s+\S') {
    throw 'Links section is empty.'
}
$map = [regex]::Match($readme, '(?s)```markmap\s+(.*?)```').Groups[1].Value
$modules = [regex]::Matches($map, '(?m)^## M(0[1-9]|1[01])\s+-').Count
if ($modules -ne 11) {
    throw "Expected 11 module branches in the markmap; found $modules."
}
```

Expected: FAIL because the current `Links` section is empty.

- [ ] **Step 2: Record the required structure**

The finished README must contain:

```text
## Links
### LP1 - Design and develop database solutions
#### M01 ... through #### M04
### LP2 - Secure, optimize, and deploy database solutions
#### M05 ... through #### M08
### LP3 - Implement AI capabilities in database solutions
#### M09 ... through #### M11
```

The markmap must contain exactly 11 `## Mxx - ...` branches and use `###` curriculum-topic branches beneath each module.

---

### Task 2: Build module-specific official reference links

**Files:**
- Modify: `README.md`
- Modify: `docs/link-ledger.txt`

**Interfaces:**
- Consumes: Learning objectives and module URLs from `docs/course-research.md`.
- Produces: M01-M11 reference lists, each beginning with its official module page.

- [ ] **Step 1: Populate `README.md` Links**

Use the verified official set:

- M01: module, Temporal Tables, In-Memory OLTP, Ledger Overview, SQL Graph Overview, CREATE PARTITION FUNCTION.
- M02: module, DML Triggers, CREATE PROCEDURE, CREATE FUNCTION, CREATE VIEW.
- M03: module, TRY...CATCH, JSON Functions, WINDOW, common table expressions.
- M04: module, GitHub Copilot in SSMS, SQL Database Projects extension, SQL MCP Server overview, repository custom instructions.
- M05: module, Always Encrypted, Dynamic Data Masking, Row-Level Security, Microsoft Entra authentication for Azure SQL.
- M06: module, Query Store, Azure SQL vCore service tiers, Query Performance Insight, execution plans.
- M07: module, SQL Database Projects, SQL Projects Automation, `Azure/sql-action`, SqlPackage.
- M08: module, Data API builder overview, SQL quickstart, SQL MCP Server overview, Azure SQL CDC.
- M09: module, CREATE EXTERNAL MODEL, AI_GENERATE_EMBEDDINGS, SQL vectors, AI functions, intelligent applications overview.
- M10: module, Full-Text Search, VECTOR_DISTANCE, VECTOR_SEARCH, CREATE VECTOR INDEX, vectors FAQ.
- M11: module, `sp_invoke_external_rest_endpoint`, CREATE DATABASE SCOPED CREDENTIAL, VECTOR_SEARCH, intelligent applications overview, SQL Server 2025 feature overview.

Mark the SQL MCP Server link as Preview in its label. Do not mark current SQL Server 2025 vector, external model, embedding, or REST endpoint pages as preview unless the fetched page itself does so.

- [ ] **Step 2: Synchronize the link ledger**

Add every new unique HTTP URL from the README to `docs/link-ledger.txt`, preserving module grouping and the existing course/lab/credential entries.

- [ ] **Step 3: Verify link policy**

```powershell
$readme = Get-Content .\README.md -Raw
if ($readme -match 'techcommunity\.microsoft\.com|stackoverflow\.com|medium\.com|azure\.microsoft\.com/en-us/pricing') {
    throw 'README contains a non-reference or non-approved source.'
}
foreach ($module in 1..11) {
    $id = 'M{0:D2}' -f $module
    if ($readme -notmatch "#### $id\b") {
        throw "Missing Links subsection $id."
    }
}
```

Expected: PASS.

---

### Task 3: Rebuild the curriculum mind map

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: PPT learning objectives and knowledge-check themes in `docs/course-research.md`.
- Produces: AI-901-style DP-800 course-outline markmap.

- [ ] **Step 1: Replace the markmap**

Use this hierarchy for every module:

```text
## Mxx - Official module title
### Curriculum topic
- Core concept or comparison from the official learning objectives
- One directly relevant official documentation link where useful
### Curriculum topic
- Core concept
```

Organize M01-M04 around database design/development, M05-M08 around secure/optimize/deploy, and M09-M11 around SQL-native AI. Keep each module to two or three `###` topic groups and approximately four to seven concise bullets. Remove resource-directory language such as `Foundations`, credential metadata, lab counts, Terraform choices, local/Azure execution notes, and trainer-only security instructions.

- [ ] **Step 2: Run the markmap structure check**

```powershell
$readme = Get-Content .\README.md -Raw
$map = [regex]::Match($readme, '(?s)```markmap\s+(.*?)```').Groups[1].Value
if ([regex]::Matches($map, '(?m)^## M(0[1-9]|1[01])\s+-').Count -ne 11) {
    throw 'Markmap does not contain exactly 11 module branches.'
}
if ([regex]::Matches($map, '(?m)^### ').Count -lt 22) {
    throw 'Each module must have at least two curriculum-topic branches.'
}
if ($map -match 'Terraform|Training key|3 Learning Paths|Exam:') {
    throw 'Markmap contains metadata instead of curriculum content.'
}
```

Expected: PASS.

---

### Task 4: Validate links and review attendee fit

**Files:**
- Modify: `README.md`
- Modify: `docs/link-ledger.txt`

**Interfaces:**
- Consumes: Completed Links and Mind Map sections.
- Produces: Verified attendee-facing README.

- [ ] **Step 1: Run the link checker**

```powershell
python .github\skills\course-prep\scripts\link_check.py docs\link-ledger.txt
```

Expected: every ledger URL returns HTTP 200 with no generic-hub fallback.

- [ ] **Step 2: Verify README URLs are represented in the ledger**

```powershell
$readmeUrls = [regex]::Matches((Get-Content .\README.md -Raw), 'https?://[^)\s>]+') |
    ForEach-Object Value |
    Sort-Object -Unique
$ledger = Get-Content .\docs\link-ledger.txt -Raw
$missing = $readmeUrls | Where-Object { $ledger -notmatch [regex]::Escape($_) }
if ($missing) {
    throw "README URLs missing from ledger: $($missing -join ', ')"
}
```

Expected: PASS.

- [ ] **Step 3: Request focused review**

Review only for:
- official-source compliance,
- direct relevance to the corresponding module,
- correct M01-M11 order and titles,
- AI-901-style curriculum hierarchy,
- absence of trainer-only environment details.
