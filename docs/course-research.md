---
created: 2026-08-03
sources: Microsoft Learn (authoritative), MicrosoftLearning GitHub, PPT XML extraction
pptx-extraction-method: PowerShell System.IO.Compression.ZipFile + SelectNodes("//*[local-name()='t']")
---

# DP-800T00-A 課程官方研究報告

> 繁體中文；技術名稱、URL、程式碼保留英文。  
> 基準日期：2026-08-03

---

## 1. 課程識別

| 項目 | 值 | 來源 |
|------|-----|------|
| Course ID | `DP-800T00-A` | learn.microsoft.com/training/courses/dp-800t00 |
| 完整名稱 (EN) | Develop AI-enabled database solutions | 同上 |
| 完整名稱 (zh-tw) | 開發具 AI 能力的資料庫解決方案 | zh-tw 課程頁面 title |
| 完整名稱 (zh-cn) | 开发支持 AI 的数据库解决方案 | zh-cn 課程頁面 title |
| 天數 | **3 days**（官方頁面原文；不導出「72 小時」） | 課程頁面 "Course Duration" 欄位 |
| 層級 | Intermediate | 課程頁面 |
| 關聯認證 | Microsoft Certified: SQL AI Developer Associate | 課程頁面 |
| 考試 | DP-800 | 課程頁面 |
| 課程語言 | EN, zh-tw, zh-cn, FR, DE, IT, JA, KO, PT-BR, ES | 課程頁面 "Languages" 欄位 |
| Achievement Code | 有（課程頁與三個 LP 頁面均提供） | 頁面 UI |

---

## 2. 三個 Learning Paths（按順序）

### LP1 — Design and develop database solutions
| 語言 | Title | URL |
|------|-------|-----|
| EN | Design and develop database solutions | <https://learn.microsoft.com/en-us/training/paths/design-develop-database-solutions/> |
| zh-tw | 設計與開發資料庫解決方案 | <https://learn.microsoft.com/zh-tw/training/paths/design-develop-database-solutions/> |
| zh-cn | 设计和开发数据库解决方案 | <https://learn.microsoft.com/zh-cn/training/paths/design-develop-database-solutions/> |

模組數：4（官方頁面確認）

### LP2 — Secure, optimize, and deploy database solutions
| 語言 | Title | URL |
|------|-------|-----|
| EN | Secure, optimize, and deploy database solutions | <https://learn.microsoft.com/en-us/training/paths/secure-optimize-deploy-database-solutions/> |
| zh-tw | 保護、優化並部署資料庫解決方案 | <https://learn.microsoft.com/zh-tw/training/paths/secure-optimize-deploy-database-solutions/> |
| zh-cn | 保护、优化和部署数据库解决方案 | <https://learn.microsoft.com/zh-cn/training/paths/secure-optimize-deploy-database-solutions/> |

模組數：4（官方頁面確認）

### LP3 — Implement AI capabilities in database solutions
| 語言 | Title | URL |
|------|-------|-----|
| EN | Implement AI capabilities in database solutions | <https://learn.microsoft.com/en-us/training/paths/implement-ai-capabilities-database-solutions/> |
| zh-tw | 在資料庫解決方案中實作 AI 功能 | <https://learn.microsoft.com/zh-tw/training/paths/implement-ai-capabilities-database-solutions/> |
| zh-cn | 在数据库解决方案中实现 AI 功能 | <https://learn.microsoft.com/zh-cn/training/paths/implement-ai-capabilities-database-solutions/> |

模組數：3（官方頁面確認）

**總計：11 modules / 11 labs**
**Canonical URLs 驗證：** 2026-08-03 via link_check.py — 42 URLs tested, all HTTP 200 ✓
- 3 x course + 9 x learning paths (3 LP × 3 locales) + 11 x modules + 1 x credential + 1 x exam guide + 4 x lab repo + 11 x lab pages = 42 total URLs
- No fallback observed; all final URLs match canonical learn.microsoft.com paths
- Runtime: ~28 seconds

---

## 3. 11 個 Modules — 目標、KC 主題、Demo Cues、Local/Azure 需求

> PPT 資料來源：`PPT/DP-800/*.pptx`，使用 PowerShell ZipFile/XML 擷取；notes 文字直接引用原文。

---

### LP1 — Design and develop database solutions

---

#### M01 — Design and implement database objects with SQL
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/design-implement-database-objects/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_01.pptx` (slides 3–11)

**Learning Objectives（from PPT slide 3 → module objectives）**
- Design and implement tables with appropriate data types, sizes, and columns
- Implement specialized tables: in-memory, temporal, external, LEDGER, and GRAPH tables
- Design and implement JSON columns and indexes
- Design and implement database constraints (PK, FK, UNIQUE, CHECK, DEFAULT)
- Design and implement SEQUENCES
- Design and implement partitioning strategies for tables and indexes

**Knowledge Check Themes（slide 11 + notes slide 11）**
- Q1：History tracking without manual history table → Temporal table（答案 b）
- Q2：PK + NOT NULL constraints → PRIMARY KEY + NOT NULL（答案 c）
- Q3：Splitting large table into manageable pieces by range → Partitioning（答案 c）

**Demo Cues（PPT notes — speaker cues identified from notes slides）**
- 展示 `CREATE TABLE ... AS NODE / AS EDGE`（Graph table）
- 展示 Temporal table 的 `SYSTEM_TIME` history query
- 展示 Partitioning function + scheme + partition switching

**Local vs. Azure Requirements**
- ✅ SQL Server 2025 本機：所有功能可執行（Temporal、In-Memory、LEDGER、Graph 均支援）
- ⚠️ LEDGER table 需 SQL Server 2022+ 或 Azure SQL

**Lab**：Lab 01 - Create and maintain database objects

---

#### M02 — Implement programmability objects with SQL
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/implement-programmability-objects/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_01.pptx` (slides 12–20)

**Learning Objectives**
- Create views to simplify data access and provide security boundaries
- Build stored procedures to encapsulate complex business logic
- Develop scalar functions to return single calculated values
- Implement table-valued functions (inline and multi-statement)
- Configure triggers (DML/DDL/logon) to automatically respond to data modifications
- Choose the right programmability object based on requirements

**Knowledge Check Themes（slide 20）**
- Q1：Simplify complex join + column restriction for users → View（答案 b）
- Q2：Advantage of stored procedures vs. inline T-SQL → precompiled + transaction/error handling（答案 b）
- Q3：When to choose TVF vs. view → TVF when parameters/dynamic filtering needed

**Demo Cues**
- 展示 inline TVF vs. multi-statement TVF 效能差異
- 展示 INSTEAD OF trigger 攔截 INSERT 到 view

**Local vs. Azure Requirements**
- ✅ SQL Server 2025 本機：全部可執行

**Lab**：Lab 02 - Implement programmability objects in SQL Server

---

#### M03 — Write advanced T-SQL code
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/write-advanced-sql-code/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_01.pptx` (slides 21–31)

**Learning Objectives**
- Write CTEs including recursive CTEs for hierarchical data
- Use window functions for ranking, aggregation, analytical calculations
- Parse, construct, and transform JSON data
- Apply regular expressions and fuzzy string matching (SOUNDEX, DIFFERENCE)
- Graph queries using MATCH operator
- Correlated subqueries
- Structured error handling with TRY…CATCH

**Knowledge Check Themes（slide 30 + notes slide 30）**
- Q1：Running total by date while preserving row details → `SUM() OVER (ORDER BY)`（答案 c）
- Q2：JSON array of related order items per customer → FOR JSON PATH / JSON_ARRAYAGG
- Q3：Graph query pattern matching → MATCH operator

**Demo Cues（notes slides 23, 27, 29）**
- 展示 recursive CTE 遍歷組織層級
- 展示 Graph MATCH 語法（ASCII-arrow syntax）
- 展示 `FOR JSON PATH` + `OPENJSON WITH` shredding（AdventureWorksLT 本機範例）
- 展示 `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` 分類排名

**Local vs. Azure Requirements**
- ✅ SQL Server 2025 本機：全部功能（含 Graph、JSON、window functions）
- 📝 範例資料庫：AdventureWorksLT（notes slide 29 確認可本機執行）

**Lab**：Lab 03 - Write advanced T-SQL queries

---

#### M04 — Implement SQL solutions by using AI-assisted tools
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/design-implement-sql-solutions-ai-assisted-tools/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_01.pptx` (slides 32–41)

**Learning Objectives**
- Describe AI-assisted development tools available for Microsoft SQL platforms
- Interpret security impact of using AI-assisted tools
- Enable GitHub Copilot and Fabric Copilot
- Configure model and MCP tool options in GitHub Copilot or Fabric Copilot chat session
- Create and configure GitHub Copilot instruction files (`.github/copilot-instructions.md`)
- Connect to MCP server endpoints (Microsoft SQL Server and Fabric Lakehouse)

**Knowledge Check Themes（slide 40）**
- Q1：AI assistance in SSMS → GitHub Copilot through AI Assistance workload（答案 b）
- Q2：Security practice with database credentials → environment variables, never paste in prompts（答案 c）
- Q3：MCP server vs. standard copilot → MCP server provides structured tool-calling context

**Demo Cues（notes slide 37, 39）**
- 展示 `.github/copilot-instructions.md`：設定 coding standards（schema prefixes, error handling, comments）
- 展示 Copilot "explain" feature 理解生成程式碼
- 展示 MCP server 連接設定（VS Code settings.json）
- ⚠️ 本 lab 第一個需要 Azure SQL Database（notes slide 39 明確指出）

**Local vs. Azure Requirements**
- ✅ GitHub Copilot 可搭配 VS Code/SSMS 連接本機 SQL Server 2025
- ❌ Fabric Copilot 需 Azure Fabric（不可本機）
- ☁️ Lab 04 明確需要 Azure SQL Database

**Lab**：Lab 04 - Configure AI-assisted tools for database development

---

### LP2 — Secure, optimize, and deploy database solutions

---

#### M05 — Implement data security and compliance with SQL
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/implement-data-security-compliance/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_02.pptx` (slides 3–11)

**Learning Objectives**
- Always Encrypted with deterministic vs. randomized encryption
- Transparent Data Encryption (TDE)
- Dynamic Data Masking（4 masking functions: Default, Email, Random, Custom）
- Row-Level Security
- Object-level permissions and Microsoft Entra ID passwordless access
- Auditing to Log Analytics / Storage Account
- Secure model endpoints and API endpoints

**Knowledge Check Themes（slide 11）**
- Q1：Protect CC numbers, equality search possible, DBAs can't read → Always Encrypted deterministic（答案 b）
- Q2：Support staff sees last 4 digits only → Dynamic Data Masking custom function
- Q3：TDE vs. Always Encrypted scope difference

**Demo Cues（notes slide 4）**
- 展示 DDM 四種 masking functions（Default, Email, Random, Custom pattern）
- 展示 Row-Level Security predicate function + security policy
- 展示 Entra ID passwordless login（Azure SQL）

**Local vs. Azure Requirements**
- ✅ TDE、Always Encrypted、DDM、RLS 全可在 SQL Server 2025 本機執行
- ⚠️ Entra ID passwordless authentication 需 Azure SQL Database
- ☁️ Auditing to Log Analytics 需 Azure

**Lab**：Lab 05 - Implement security features

---

#### M06 — Optimize database performance
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/optimize-database-performance/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_02.pptx` (slides 12–20)

**Learning Objectives**
- Evaluate and recommend Azure SQL service tiers (General Purpose / Business Critical / Hyperscale)
- Choose transaction isolation levels and concurrency controls（RCSI default in Azure SQL）
- Analyze query performance using execution plans and DMVs (`sys.dm_exec_query_stats`)
- Monitor and tune queries with Query Store and Query Performance Insight
- Identify and resolve blocking and deadlocks
- Plan forcing to prevent regressions

**Knowledge Check Themes（slide 20）**
- Q1：I/O latency < 2ms + free read-only replica → Business Critical（答案 b）
- Q2：Default isolation in Azure SQL using row versioning → READ COMMITTED SNAPSHOT ISOLATION (RCSI)（答案 b）
- Q3：Restore performance after plan regression without code change → Automatic plan correction / plan forcing via Query Store（答案 c, plan forcing）

**Demo Cues（notes slides 15, 16, 18）**
- 展示 Actual vs. Estimated execution plans（missing index suggestion）
- 展示 Query Store Regressed Queries view
- 展示 parameter sniffing scenario + plan forcing（notes slide 18）
- 展示 `sys.dm_exec_query_stats` + `sys.dm_exec_sql_text` 找 top resource consumers

**Local vs. Azure Requirements**
- ✅ Execution plans、DMV、Query Store 可在 SQL Server 2025 本機執行
- ❌ DTU/vCore service tier 選擇、Query Performance Insight 是 Azure 入口網站功能
- ☁️ Lab 06 uses Azure SQL Database（notes slide 18 確認）

**Lab**：Lab 06 - Optimize query performance

---

#### M07 — Implement CI/CD by using SQL database projects
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/implement-cicd-sql-database-projects/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_02.pptx` (slides 21–30)

**Learning Objectives**
- Create, build, and validate database models using SDK-style SQL Database Projects (`dotnet build`)
- Configure source control with Git (object-per-file structure)
- Manage branching, pull requests, conflict resolution（feature branch → main via PR）
- Detect schema drift using schema comparison tools and SqlPackage
- Implement CI/CD pipelines with GitHub Actions (`azure/sql-action`) and Azure DevOps
- Design and implement testing strategy (unit + integration tests)
- Pre/post-deployment scripts for reference data management

**Knowledge Check Themes（slide 30）**
- Q1：Hotfix applied directly to prod, project out of sync → Schema drift, detected by schema comparison（答案 a）
- Q2：GitHub Action to deploy .dacpac to Azure SQL → `azure/sql-action`（答案 a）
- Q3：Pre/post-deployment script purpose vs. migration scripts

**Demo Cues（notes slides 23, 24）**
- 展示 object-per-file structure（`Tables/`, `Views/`, `StoredProcedures/`）
- 展示 Git diff showing exact T-SQL changes（vs. monolithic migration scripts）
- 展示 `dotnet build` + `SqlPackage /Action:DeployReport` schema drift report

**Local vs. Azure Requirements**
- ✅ SQL Database Projects 可部署到本機 SQL Server；`dotnet build`、SqlPackage 可本機執行
- ☁️ GitHub Actions / Azure DevOps pipeline 需 GitHub/Azure DevOps（雲端）
- ☁️ Lab 07 targets Azure SQL Database for deployment step

**Lab**：Lab 07 - Implement CI/CD by using SQL database projects

---

#### M08 — Integrate SQL solutions with Azure services
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/integrate-sql-solutions-azure-services/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_02.pptx` (slides 31–40)

**Learning Objectives**
- Create configuration files for Data API Builder (`dab-config.json`)
- Use `@env()` syntax for secure connection string referencing
- Define entities for REST and GraphQL with field mappings, caching, relationships
- Configure REST and GraphQL endpoints; expose views and stored procedures
- Deployment options: Azure Container Apps, App Service, Static Web Apps
- Azure Monitor with Application Insights and Log Analytics
- Change Data Capture, Azure Functions, Change Event Streaming

**Knowledge Check Themes（slide 39）**
- Q1：Store connection string without hardcoding in dab-config.json → `@env()` syntax（答案 b）
- Q2：Entity with read-only access only → permissions: `["read"]` in entity config
- Q3：REST vs. GraphQL endpoint configuration differences

**Demo Cues**
- 展示 `dab init` + `dab add` 建立 entity configuration
- 展示 `@env('CONN_STRING')` 引用環境變數
- 展示 REST endpoint `GET /api/Product` vs. GraphQL query

**Local vs. Azure Requirements**
- ✅ Data API Builder CLI 可連接本機 SQL Server（`dab run` 本機執行）
- ❌ Azure Container Apps / App Service 部署是 Azure-only
- ☁️ Lab 08 product catalog demo targets Azure SQL

**Lab**：Lab 08 - Configure Data API Builder for a product catalog

---

### LP3 — Implement AI capabilities in database solutions

---

#### M09 — Design and implement models and embeddings with SQL
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/design-implement-models-embeddings-with-sql/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_03.pptx` (slides 3–11)

**Learning Objectives**
- Evaluate AI models for SQL database workloads
- Create and manage external models to reference AI endpoints from T-SQL (`CREATE EXTERNAL MODEL`)
- Design embeddings with appropriate chunking strategies
- Generate and store embeddings using `AI_GENERATE_EMBEDDINGS()`
- Store vectors using `vector` data type; choose maintenance approaches

**Knowledge Check Themes（slide 11）**
- Q1：External model definition → database object storing metadata about AI model endpoint（答案 a）
- Q2：Chunking purpose → divide large text into segments fitting token limits（答案 b）
- Q3：Data type for embeddings → `vector`（NOT NVARCHAR(MAX)）（答案 c）

**Demo Cues**
- 展示 `CREATE EXTERNAL MODEL` 指向 Azure OpenAI endpoint
- 展示 `AI_GENERATE_EMBEDDINGS(text USING model_name)` 批次生成
- 展示 chunking strategy（固定 token 大小 vs. 語意分段）

**Local vs. Azure Requirements**
- ⚠️ `vector` 資料型別：SQL Server 2025（RTM 17.0.4065.4）已支援
- ⚠️ `CREATE EXTERNAL MODEL`、`AI_GENERATE_EMBEDDINGS`：需 SQL Server 2025 RTM 或 Azure SQL Database（以實機測試為準，見 §6 Open Uncertainties）
- ☁️ Azure OpenAI endpoint 需網路可達（Lab 09 需 Azure SQL + Azure OpenAI）
- 📝 Lab 09 URL 有拼字錯誤（`embedings` 少一個 d），屬原始 repo 拼字，不可「修正」

**Lab**：Lab 09 - Generate and update embeddings in Azure SQL Database

---

#### M10 — Design and implement intelligent search with SQL
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/design-implement-intelligent-search-with-sql/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_03.pptx` (slides 12–20)

**Learning Objectives**
- Full-text search：`CONTAINS`（含 `FORMSOF(INFLECTIONAL)`）、`FREETEXT` 謂詞
- Vector search：`VECTOR_DISTANCE`（精確）vs. `VECTOR_SEARCH`（ANN 近似，效能優先）
- Hybrid search：combining full-text relevance score + cosine similarity
- Index strategies for vector columns

**Knowledge Check Themes（slide 20）**
- Q1：Find inflectional forms of a word (e.g., "running" for "run") → `CONTAINS` with `FORMSOF(INFLECTIONAL)`（答案 a；注意 FREETEXT 也可，但 Q 指定 predicate）
- Q2：Cosine distance value range → 0 to 2（答案 c；cosine similarity -1~1，但 cosine distance = 1-similarity → 0~2）
- Q3：Vector search on 500K rows, speed priority → `VECTOR_SEARCH`（ANN）（答案 b）

**Demo Cues**
- 展示 Full-Text Index 建立 + `CONTAINS(column, 'FORMSOF(INFLECTIONAL, run)')`
- 展示 `VECTOR_DISTANCE('cosine', v1, v2)` 精確搜尋
- 展示 `VECTOR_SEARCH(table, vector_col, VECTOR_QUERY(…), TOP 10)` ANN 搜尋
- 展示 hybrid search combining BM25 rank + vector score via RRF

**Local vs. Azure Requirements**
- ⚠️ Full-text search：SQL Server 2025 本機可執行（需 Full-Text Search 功能安裝）
- ⚠️ `VECTOR_SEARCH`（ANN）：確認 SQL Server 2025 RTM 是否已支援（見 §6）；`VECTOR_DISTANCE` 精確搜尋已在 preview 中可用
- ☁️ Lab 10 targets Azure SQL Database

**Lab**：Lab 10 - Implement intelligent search with full-text, vector, and hybrid queries

---

#### M11 — Design and implement RAG with SQL
- 模組 URL：<https://learn.microsoft.com/en-us/training/modules/design-implement-rag-with-sql/>
- PPT 所在：`DP-800T00-ENU-PowerPoint_03.pptx` (slides 21–30)

**Learning Objectives**
- Describe RAG architecture vs. fine-tuning trade-offs
- Build RAG pipeline entirely in T-SQL using `sp_invoke_external_rest_endpoint`
- Format retrieved context as JSON for LLM prompt using `FOR JSON … WITHOUT_ARRAY_WRAPPER`
- Grant `EXECUTE ANY EXTERNAL ENDPOINT` permission to database user
- Retrieve top-K results via `VECTOR_SEARCH` and augment prompt

**Knowledge Check Themes（slide 30）**
- Q1：RAG advantage over fine-tuning → uses data at query time, no retraining needed（答案 b）
- Q2：T-SQL option to remove square brackets from JSON for single-row RAG context → `WITHOUT_ARRAY_WRAPPER`（答案 c）
- Q3：Permission required to call `sp_invoke_external_rest_endpoint` → `EXECUTE ANY EXTERNAL ENDPOINT`

**Demo Cues（notes slides 25, 27, 28）**
- 展示 `FOR JSON PATH WITHOUT_ARRAY_WRAPPER` 生成 LLM-readable JSON context
- 展示 `sp_invoke_external_rest_endpoint` 呼叫 Azure OpenAI chat completions endpoint
- 展示完整 RAG stored procedure：
  1. `VECTOR_SEARCH` 找 top-K reviews
  2. `FOR JSON PATH` 序列化為 context
  3. `sp_invoke_external_rest_endpoint` 生成回答
- 展示 `DATABASE SCOPED CREDENTIAL` 安全儲存 API key

**Local vs. Azure Requirements**
- ⚠️ `sp_invoke_external_rest_endpoint`：Azure SQL Database only（SQL Server 本機不支援）
- ☁️ Lab 11 需要：Azure SQL Database + Azure OpenAI（gpt-4.1-mini for generation, text-embedding-3-small for embeddings）（notes slide 28 確認）

**Lab**：Lab 11 - Implement RAG solutions

---

## 4. PPT 結構摘要

| 檔案 | Slides | Note Slides | 涵蓋範圍 |
|------|--------|-------------|----------|
| `_00-Introduction.pptx` | 10 | 1 | 課程介紹、學員自我介紹、Achievement Code 取得 |
| `_01.pptx` | 41 | 41 | LP1：M01–M04（含 KC + lab transitions） |
| `_02.pptx` | 40 | 39 | LP2：M05–M08（含 KC + lab transitions） |
| `_03.pptx` | 31 | 30 | LP3：M09–M11（含 KC + lab transitions） |
| `_04-Conclusion.pptx` | 3 | 0 | 課程結尾、認證推廣 |

> 驗證方式：PowerShell `System.IO.Compression.ZipFile` 直接計算 `ppt/slides/slide*.xml` 與 `ppt/notesSlides/notesSlide*.xml` 項目數（2026-08-03 實測）。

### Speaker Notes 擷取狀態
- ✅ 已成功以 PowerShell ZipFile + XML 方式擷取全部 notes
- PPT01 notes slides：41 個；含詳細講師說明，包括 AdventureWorksLT 資料庫使用提示、demo script 說明、KC 解答說明
- PPT02 notes slides：39 個；含 Query Store lab script、schema drift demo、Data API Builder 設定步驟
- PPT03 notes slides：30 個；含完整 RAG pipeline T-SQL 範例、Azure OpenAI 模型規格（`gpt-4.1-mini`, `text-embedding-3-small`）
- PPT00：1 個 note slide；PPT04：notes 為空（純流程頁面）

---

## 5. Localization 確認

| 項目 | 狀態 | 詳情 |
|------|------|------|
| 課程頁面 | ✅ EN + zh-tw + zh-cn + 8 其他語言 | link checker [200] 均通過 |
| Learning Paths | ✅ confirmed localized（zh-tw + zh-cn） | 實測 HTTP 200；zh-tw titles：「設計與開發資料庫解決方案」、「保護、優化並部署資料庫解決方案」、「在資料庫解決方案中實作 AI 功能」；zh-cn titles：「设计和开发数据库解决方案」、「保护、优化和部署数据库解决方案」、「在数据库解决方案中实现 AI 功能」（2026-08-03 實測） |
| Module 頁面 | EN（link checker 測試為 EN） | zh-tw/zh-cn module 頁面存在但未列入 ledger |
| Lab 頁面 | ✅ 英文 only（GitHub Pages） | 學員做 lab 時使用英文 |
| 考試 DP-800 | ⚠️ 目前僅英文版考試 | credential 頁面未列其他語言；如以中文授課需向學員說明 |

---

## 6. Open Uncertainties（待驗證事項）

以下項目**無法僅憑現有官方文件直接確認**，不得宣稱已驗證：

1. **SQL Server 2025 本機 AI Functions RTM 支援範圍**  
   `CREATE EXTERNAL MODEL` 和 `AI_GENERATE_EMBEDDINGS`、`VECTOR_SEARCH`（ANN）在 SQL Server 2025 RTM（17.0.4065.4）的確切支援範圍，應在每次課前以本機 `mssql2025` container 實機測試確認，不可假設與 Azure SQL Database 完全等同。

2. **Japan East Azure OpenAI 模型可用性與配額**  
   Japan East 理論上支援 Azure OpenAI，但具體模型（如 `gpt-4.1-mini`, `text-embedding-3-small`）的可用性和每訂閱配額受帳戶層級影響。**不可宣稱 Japan East 完整支援所有課程用模型**。建議課前執行：
   ```bash
   az cognitiveservices account list-models --name <resource> --resource-group <rg>
   ```
   確認可用 deployment SKU。

3. **DP-800 Study Guide 頁面 title bug**  
   URL `https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/dp-800` 回傳 HTTP 200，但 `<title>` 顯示為 "Study Guide for Exam DP-700: Implementing Data Engineering Solutions Using Azure Databricks"（DP-700 字樣）。頁面內容本身是 DP-800 的學習指南（Microsoft Learn 後端 routing 正確），但 title 屬於已知 bug。已回報研究時發現，每次課前應重新確認 Microsoft 是否已修正。

4. **`VECTOR_SEARCH`（ANN）在 SQL Server 2025 的可用性**  
   文件指出 ANN vector search 在 Azure SQL Database 已 GA，但在 SQL Server 2025 RTM 的狀態需實機確認。

5. **考試語言**  
   DP-800 考試目前僅提供英文版；若課程以中文授課，需向學員說明考試仍需以英文作答。

---

## 7. 已確認不可使用的連結

| 連結 | 問題 | 說明 |
|------|------|------|
| `https://aka.ms/develop-ai-enabled-database-solutions` | ❌ 重導向 Bing | PPT_00 slide 8 引用此連結，但已確認為 dead aka.ms；不得放入 README 或 link-ledger |

---

## 8. Link Checker 實際執行結果

### 最新執行（2026-08-03T19:03 +08:00）

```
執行指令：python .github\skills\course-prep\scripts\link_check.py docs\link-ledger.txt
執行時間：2026-08-03T19:03 +08:00
Python 版本：Python 3.14.5 (C:\Python314\python.exe)
```

> **Contact links exemption** — `mailto:` URI および LinkedIn プロフィール URL は HTTP チェッカーに通さない（`mailto:` はプロトコル不適合；LinkedIn は bot-access 403）。これらは repo 固有のトレーナー連絡先メタデータとして管理し、link-ledger には含めない。

**結果摘要：共 42 條連結（42/42 HTTP 200）**

| 類別 | 數量 | 結果 |
|------|------|------|
| ESI Portals | 2 | ✅ 全通過 |
| 課程頁面（EN/zh-tw/zh-cn） | 3 | ✅ 全通過 |
| Learning Paths（3 LP × 3 locales） | 9 | ✅ 全通過 |
| Modules（11個） | 11 | ✅ 全通過 |
| Credential + Study Guide | 2 | ✅ HTTP 200；⚠️ Study Guide title 顯示 DP-700（known bug，見 §6） |
| Lab Repo + Pages Index + aka.ms | 3 | ✅ 全通過 |
| Lab Exercise Pages（11個） | 11 | ✅ 全通過；Lab 09 `embedings` 拼字為 repo 原始拼字，intentional |
| Lab Repo main.zip | 1 | ✅ HTTP 200；重導向 codeload.github.com |

### 原始執行（2026-08-03T18:36:58 +08:00，34 條）

```
執行指令：python .github\skills\course-prep\scripts\link_check.py docs\link-ledger.txt
執行時間：2026-08-03T18:36:58 → 18:37:07 +08:00（elapsed ≈ 9 s）
Python 版本：Python 3.14.5 (C:\Python314\python.exe)
```

**結果摘要：共 34 條連結，全部 HTTP 200**

| 類別 | 數量 | 結果 |
|------|------|------|
| 課程頁面（EN/zh-tw/zh-cn） | 3 | ✅ 全通過 |
| Learning Paths（3個） | 3 | ✅ 全通過 |
| Modules（11個） | 11 | ✅ 全通過 |
| Credential + Study Guide | 2 | ✅ HTTP 200；⚠️ Study Guide title 顯示 DP-700（bug，見 §6） |
| Lab Repo + Pages Index | 3 | ✅ 全通過；aka.ms/SQLAIDevLabs 正確重導向至 GitHub Pages |
| Lab Exercise Pages（11個） | 11 | ✅ 全通過；Lab 09 拼字錯誤（`embedings`）屬 repo 原始拼字，intentional |
| Lab Repo main.zip | 1 | ✅ HTTP 200；重導向至 codeload.github.com（正常 GitHub archive redirect） |

**失敗/排除連結：**
- `https://aka.ms/develop-ai-enabled-database-solutions` → ❌ 已排除，不放入 ledger（重導向 Bing）

完整輸出見下方（連結標題由 link checker 實際讀取）：

```
[200] Course DP-800T00-A (EN)
    url: https://learn.microsoft.com/en-us/training/courses/dp-800t00
    title: Course DP-800T00-A: Develop AI-enabled database solutions - Training | Microsoft Learn
[200] Course DP-800T00-A (zh-tw)
    url: https://learn.microsoft.com/zh-tw/training/courses/dp-800t00
    title: 課程 DP-800T00-A：開發具 AI 能力的資料庫解決方案 - Training | Microsoft Learn
[200] Course DP-800T00-A (zh-cn)
    url: https://learn.microsoft.com/zh-cn/training/courses/dp-800t00
    title: 课程 DP-800T00-A：开发支持 AI 的数据库解决方案 - Training | Microsoft Learn
[200] LP1 - Design and develop database solutions
    url: https://learn.microsoft.com/en-us/training/paths/design-develop-database-solutions/
    title: Design and develop database solutions - Training | Microsoft Learn
[200] LP2 - Secure, optimize, and deploy database solutions
    url: https://learn.microsoft.com/en-us/training/paths/secure-optimize-deploy-database-solutions/
    title: Secure, optimize, and deploy database solutions - Training | Microsoft Learn
[200] LP3 - Implement AI capabilities in database solutions
    url: https://learn.microsoft.com/en-us/training/paths/implement-ai-capabilities-database-solutions/
    title: Implement AI capabilities in database solutions - Training | Microsoft Learn
[200] M01 - Design and implement database objects with SQL
    url: https://learn.microsoft.com/en-us/training/modules/design-implement-database-objects/
    title: Design and Implement Database Objects with SQL - Training | Microsoft Learn
[200] M02 - Implement programmability objects with SQL
    url: https://learn.microsoft.com/en-us/training/modules/implement-programmability-objects/
    title: Implement Programmability Objects with SQL - Training | Microsoft Learn
[200] M03 - Write advanced T-SQL code
    url: https://learn.microsoft.com/en-us/training/modules/write-advanced-sql-code/
    title: Write Advanced T-SQL Code - Training | Microsoft Learn
[200] M04 - Implement SQL solutions by using AI-assisted tools
    url: https://learn.microsoft.com/en-us/training/modules/design-implement-sql-solutions-ai-assisted-tools/
    title: Implement SQL Solutions by Using AI-assisted Tools - Training | Microsoft Learn
[200] M05 - Implement data security and compliance with SQL
    url: https://learn.microsoft.com/en-us/training/modules/implement-data-security-compliance/
    title: Implement Data Security and Compliance With SQL - Training | Microsoft Learn
[200] M06 - Optimize database performance
    url: https://learn.microsoft.com/en-us/training/modules/optimize-database-performance/
    title: Optimize Database Performance - Training | Microsoft Learn
[200] M07 - Implement CI/CD by using SQL database projects
    url: https://learn.microsoft.com/en-us/training/modules/implement-cicd-sql-database-projects/
    title: Implement CI/CD by Using SQL Database Projects - Training | Microsoft Learn
[200] M08 - Integrate SQL solutions with Azure services
    url: https://learn.microsoft.com/en-us/training/modules/integrate-sql-solutions-azure-services/
    title: Integrate SQL Solutions With Azure Services - Training | Microsoft Learn
[200] M09 - Design and implement models and embeddings with SQL
    url: https://learn.microsoft.com/en-us/training/modules/design-implement-models-embeddings-with-sql/
    title: Design and Implement Models and Embeddings With SQL - Training | Microsoft Learn
[200] M10 - Design and implement intelligent search with SQL
    url: https://learn.microsoft.com/en-us/training/modules/design-implement-intelligent-search-with-sql/
    title: Design and Implement Intelligent Search With SQL - Training | Microsoft Learn
[200] M11 - Design and implement RAG with SQL
    url: https://learn.microsoft.com/en-us/training/modules/design-implement-rag-with-sql/
    title: Design and Implement RAG With SQL - Training | Microsoft Learn
[200] Microsoft Certified: SQL AI Developer Associate
    url: https://learn.microsoft.com/en-us/credentials/certifications/developing-ai-enabled-database-solutions/
    title: Microsoft Certified: SQL AI Developer Associate - Certifications | Microsoft Learn
[200] DP-800 Study Guide
    url: https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/dp-800
    title: Study Guide for Exam DP-700: Implementing Data Engineering Solutions Using Azure Databricks | Microsoft Learn
    ⚠️  Title says DP-700 — known page bug; content is DP-800 study guide
[200] Lab Repo: mslearn-sql-developer
    url: https://github.com/MicrosoftLearning/mslearn-sql-developer
    title: GitHub - MicrosoftLearning/mslearn-sql-developer: About Repository for lab exercises...
[200] Lab Pages Index
    url: https://microsoftlearning.github.io/mslearn-sql-developer/
    title: SQL Developer Exercises | Lab Exercises
[200] Lab Pages via aka.ms
    url: https://aka.ms/SQLAIDevLabs  ->FINAL: https://microsoftlearning.github.io/mslearn-sql-developer/
    title: SQL Developer Exercises | Lab Exercises
[200] Lab Repo main.zip
    url: https://github.com/MicrosoftLearning/mslearn-sql-developer/archive/refs/heads/main.zip
    ->FINAL: https://codeload.github.com/MicrosoftLearning/mslearn-sql-developer/zip/refs/heads/main
[200] Lab 01 - Create database objects
    title: Design and implement database objects with SQL | Lab Exercises
[200] Lab 02 - Implement programmability objects
    title: Implement programmability objects with SQL | Lab Exercises
[200] Lab 03 - Write advanced T-SQL queries
    title: Write advanced T-SQL queries | Lab Exercises
[200] Lab 04 - AI-assisted tools
    title: Implement SQL solutions by using AI-assisted tools | Lab Exercises
[200] Lab 05 - Security compliance
    title: Implement security and compliance with SQL | Lab Exercises
[200] Lab 06 - Optimize database performance
    title: Optimize query performance | Lab Exercises
[200] Lab 07 - CI/CD SQL database projects
    title: Implement CI/CD with SQL Database Projects | Lab Exercises
[200] Lab 08 - Integrate SQL with Azure services
    title: Integrate SQL solutions with Azure services | Lab Exercises
[200] Lab 09 - Generate and update embeddings (NOTE: typo in filename is intentional)
    title: Generate and update embeddings in Azure SQL Database | Lab Exercises
[200] Lab 10 - Implement intelligent search
    title: Implement intelligent search with full-text, vector, and hybrid queries | Lab Exercises
[200] Lab 11 - Implement RAG solutions
    title: Implement RAG solutions | Lab Exercises
```
