---
tags: DP-800, Trainer, Teaching
---

# DP-800 備課指南（Trainer-only）

> 本文件僅供講師備課與授課使用，不是學員講義。學員入口、日期、Course ID、Survey、Skillable 與 Training key 以 [`README.md`](../README.md) 當次資料為準；備課時只核對，不在本文件複製或改寫。
>
> Demo 有兩條互補路徑：可重設的本機 SQL Server 2025（[`DEMO/`](../DEMO/)）與 Azure 備援環境（[`TERRAFORM/`](../TERRAFORM/)）。目前只完成 Terraform 靜態驗證與 plan；**尚未完成真實 Azure `apply`、AI data-plane smoke test 與 `destroy`，不得宣稱 Azure 端到端已通過。**

---

## 1. 課程定位與三天交付目標

| 項目 | 內容 |
| --- | --- |
| Course | **DP-800T00-A: Develop AI-enabled database solutions** |
| 中文定位 | 開發具 AI 能力的資料庫解決方案 |
| 時長／層級 | 3 days／Intermediate |
| 對象 | SQL developer、database developer、data professional，以及需把 AI 能力整合到 SQL solution 的開發人員 |
| 建議先備 | 基本 T-SQL、relational database、Git／CI/CD 概念；能閱讀英文 Lab；具 Azure、Microsoft Entra ID、REST API 基礎更佳 |
| 關聯認證 | Microsoft Certified: SQL AI Developer Associate；考試 DP-800 |
| 官方課程 | [Course DP-800T00-A](https://learn.microsoft.com/en-us/training/courses/dp-800t00) |

### 三天結束時，學員應能

1. 以合適的 database objects、programmability objects 與 advanced T-SQL 建立可維護的資料層。
2. 將 security、performance、database project CI/CD 與 Azure service integration 納入 solution lifecycle。
3. 說明並實作 model／embedding、exact／ANN／hybrid search，以及以 SQL 組合的 RAG flow。
4. 清楚區分 SQL Server 2025 本機能力、Azure SQL 能力與 preview／版本敏感語法，不把兩者視為完全相同。
5. 能檢查 AI 產生的 SQL、保護 credential、處理 endpoint error，而不是把生成結果直接當成正確答案。

### 3 Learning Paths／11 Modules／11 Labs

| Learning Path | Modules | 核心進程 |
| --- | --- | --- |
| [LP1 — Design and develop database solutions](https://learn.microsoft.com/en-us/training/paths/design-develop-database-solutions/) | M01–M04 | Objects → programmability → advanced T-SQL → AI-assisted development |
| [LP2 — Secure, optimize, and deploy database solutions](https://learn.microsoft.com/en-us/training/paths/secure-optimize-deploy-database-solutions/) | M05–M08 | Security → performance → CI/CD → Azure integration |
| [LP3 — Implement AI capabilities in database solutions](https://learn.microsoft.com/en-us/training/paths/implement-ai-capabilities-database-solutions/) | M09–M11 | Models／embeddings → intelligent search → RAG |

官方 Lab 為英文，共 11 個；入口為 [DP-800 Lab Pages](https://microsoftlearning.github.io/mslearn-sql-developer/)。

---

## 2. 開課前檢查清單

建議於開課前 1–2 天完成，開課當日上午再做一次短版檢查。

### 2.1 學員與課務資料

- [ ] 核對 `README.md` 中 Date、Course ID、Survey、ESI／Skillable 入口與 Training key；**不要在 trainer guide 重複或改動 attendee metadata**。
- [ ] 確認學員可登入 [ESI Labs](https://aka.ms/esilab)；準備 [ESI Support](https://aka.ms/esisupport)。
- [ ] 提醒 Training key 只能兌換一次、Lab instruction 為英文。
- [ ] 確認 PPT 使用 `PPT/DP-800/`，不要混用舊 DP-300 或過期課程素材。
- [ ] 檢查 introduction／conclusion 中的 course title、credential 與連結；不要使用已失效的舊 `aka.ms`。

### 2.2 PPT 與授課節奏

- [ ] 預讀 `PPT/DP-800/DP-800T00-ENU-PowerPoint_00-Introduction.pptx`。
- [ ] LP1 使用 `PPT/DP-800/DP-800T00-ENU-PowerPoint_01.pptx`；LP2 使用 `_02.pptx`；LP3 使用 `_03.pptx`。
- [ ] 結尾使用 `PPT/DP-800/DP-800T00-ENU-PowerPoint_04-Conclusion.pptx`。
- [ ] 每個 module 採一致節奏：**module opener／objectives → concept progression → comparison or demo cue → Knowledge Check → Lab transition**。
- [ ] 不依投影片編號口述；不同版本可能重排。以 module title、section title 與 speaker notes cue 對位。

### 2.3 本機 SQL Server 2025

- [ ] 確認既有 Docker container `mssql2025` 已由外部流程啟動；repo 不負責建立、啟停或刪除 container。
- [ ] 安裝 PowerShell 7 與 `sqlcmd`。
- [ ] 密碼只從 `DP800_SQL_PASSWORD`、`SQLCMDPASSWORD` 或 secure prompt 取得；不得放入 script、argument、`.env`、文件、截圖或 Git。
- [ ] DEMO 文件以英文 `README.md` 與繁體中文 `README.zh-TW.md` 同目錄成對維護；請由根目錄的 [`DEMO/README.md`](../DEMO/README.md) 或 [`DEMO/README.zh-TW.md`](../DEMO/README.zh-TW.md) 進入，兩版的可執行命令必須相同。
- [ ] 執行 `pwsh DEMO/bootstrap/Invoke-Bootstrap.ps1`，確認只建立**單一** `AdventureGearAI` 資料庫（含 `catalog`／`sales`／`customer`／`security`／`ops`／`api`／`search`／`ai` schema、`ops.DemoEnvironment` marker、`ops.DemoModuleState` 與 canonical AdventureGear ecommerce seed）。
- [ ] 確認 bootstrap 不建立 per-module 資料庫；任何殘留的 legacy `DP800_Mxx` 只會被列為 manual cleanup candidate，永不自動刪除（never automatically deleted）。
- [ ] 需要時以 hybrid runner 跑 module：`pwsh DEMO/scripts/Invoke-DemoModule.ps1 -Modules <n>`（或 `Invoke-Bootstrap.ps1 -Modules <n>`）；不加 `-Modules` 則 core-only。
- [ ] 已完成的本機實測結果應直接講清楚：
  - regular expression、`vector` type／exact vector、`sys.external_models` catalog 與 `sp_invoke_external_rest_endpoint` catalog/procedure surface 可偵測或支援；
  -目前 image **沒有安裝 Full-Text Search**；
  - `ALLOW_STALE_VECTOR_INDEX`／舊 ANN configuration 在本機不支援，因此 local ANN 會 truthful skip；
  - DAB CLI 目前未安裝，M08 本機 API live demo 前需另行安裝。
- [ ] 本機結果只代表當次 image/build；delivery day 再執行 feature detection，不用記憶推斷。

### 2.4 Azure／Terraform

- [ ] 先讀 [`docs/demo-environment.md`](./demo-environment.md) 與 [`TERRAFORM/README.md`](../TERRAFORM/README.md)。
- [ ] 確認 subscription、tenant、active identity、region、provider registration、role assignment 權限。
- [ ] **所有主要 feature toggles 預設為 `true`**；default plan 是完整且昂貴的 gallery，不適合無檢查直接部署。
- [ ] 課程通常只需選擇性預建 AI-only stack：保留 `enable_core_sql_ai=true`，停用 gallery、MI、兩台 SQL VM、PostgreSQL 與 operations。
- [ ] SQL Managed Instance、SQL VMs、Hyperscale、elastic pool、PostgreSQL、Database Watcher 等只在確定要示範時預建；MI 建立／刪除時間尤其長。
- [ ] 需要 password-based gallery 時，只用 secure prompt 暫存到 process environment；saved plan 也可能含 sensitive values，需視為 secret。
- [ ] 開課前完成真實 plan／apply／data-plane／output／destroy 才能把 Azure backup 標記為 delivery-ready。現況不可如此宣稱。

### 2.5 Model、quota 與 secrets

- [ ] 重新確認 `text-embedding-3-small` 與 chat model 的版本、GA／preview、deployment type、region availability、subscription quota 與即時 capacity。
- [ ] Repo AI stack 目前以 `text-embedding-3-small`、`VECTOR(1536)` 與 `gpt-5.4-mini` 為實作基準；PPT／Lab 若使用不同 chat model，說明那是教材情境，不要宣稱部署完全相同。
- [ ] Embedding dimension 必須與 model output 完全一致；換 model 時要同步檢查 table column、index、stored procedure 與既有 embeddings。
- [ ] Azure path 採 Entra／managed identity；不展示或記錄 Azure OpenAI API key。
- [ ] Prompt、Copilot chat、Lab notes、terminal output 與錄影不得含 production data、token、password、connection string 或真實個資。

---

## 3. 建議三天議程

原則：每天約 6.5 小時教學活動，保留固定休息與 30–45 分鐘 buffer。11 個 Lab 不宜全部逐步帶做；可依班級速度，把部分改成 instructor walkthrough 或課後完成。

**單一資料庫、三天演進的節奏**：三天都在同一個 `AdventureGearAI` 資料庫上授課，不是 11 個彼此獨立的 `DP800_Mxx`。Day 1 建立 schema、programmability 與 advanced T-SQL；Day 2 疊上 security、performance、CI/CD 與 API；Day 3 讓同一批 products／customers／reviews 進入 embedding、search 與 RAG。hybrid runner 依賴圖自動補齊 prerequisite（cumulative M01 → M11），因此可以「請哪個 module 就自動先跑它需要的 module」，而 canonical core 只建立一次。請以「同一個資料庫逐步長出能力」的故事線串連每個 module，而非每組重新建庫。

### Day 1 — LP1：Design and develop

| 時段 | 內容 | Delivery |
| --- | --- | --- |
| 09:00–09:30 | 開場、課程地圖、環境與 Skillable 檢查 | Introduction PPT |
| 09:30–10:35 | M01 + local demo | Lab 01 起步或 walkthrough |
| 10:35–10:50 | 休息 |  |
| 10:50–11:55 | M02 + local demo | Lab 02 |
| 11:55–12:10 | Buffer／KC 回顧 |  |
| 12:10–13:10 | 午休 |  |
| 13:10–14:25 | M03 + local demo | Lab 03 |
| 14:25–14:40 | 休息 |  |
| 14:40–15:45 | M04 AI-assisted workflow | Lab 04；Azure SQL／approved Copilot path |
| 15:45–16:25 | Day 1 integration exercise | 比較 view／procedure／AI review 的責任邊界 |
| 16:25–17:00 | Q&A、補 Lab、buffer |  |

### Day 2 — LP2：Secure, optimize, deploy

| 時段 | 內容 | Delivery |
| --- | --- | --- |
| 09:00–09:15 | Day 1 recap | objects → lifecycle |
| 09:15–10:25 | M05 + local security demo | Lab 05 |
| 10:25–10:40 | 休息 |  |
| 10:40–12:00 | M06 + coordinated blocking/deadlock demo | Lab 06 |
| 12:00–13:00 | 午休 |  |
| 13:00–14:10 | M07 project build／pipeline | Lab 07 |
| 14:10–14:25 | 休息 |  |
| 14:25–15:35 | M08 DAB／Azure integration | Lab 08；DAB CLI 若未備妥改 walkthrough |
| 15:35–16:10 | Azure service-tier／hosting comparison | 可用預建畫面，不必建立昂貴 gallery |
| 16:10–17:00 | Buffer、Lab completion、LP2 recap |  |

### Day 3 — LP3：AI capabilities

| 時段 | 內容 | Delivery |
| --- | --- | --- |
| 09:00–09:20 | AI stack、identity、model／dimension recap | 先說明 local／Azure boundary |
| 09:20–10:45 | M09 external model／embeddings | Lab 09；AI-only Azure stack宜預建 |
| 10:45–11:00 | 休息 |  |
| 11:00–12:20 | M10 exact／ANN／hybrid search | Lab 10；Azure ANN 預建、local exact live |
| 12:20–13:20 | 午休 |  |
| 13:20–14:50 | M11 RAG flow／REST error handling | Lab 11；Azure endpoint宜預建 |
| 14:50–15:05 | 休息 |  |
| 15:05–16:00 | End-to-end narrative | embedding → retrieval → context → generation |
| 16:00–16:30 | Credential／study resources／Q&A | 不承諾 exam coverage |
| 16:30–17:00 | Cleanup／destroy ownership／survey | 保留 teardown buffer |

### 建議預建策略

- **優先預建**：M09–M11 的 Azure SQL AI-only stack、model deployments、RBAC、sample data 與必要 index；課堂上重點展示 SQL 與結果，不等待 model deploy／embedding batch。
- **按需預建**：M04、M06–M08 所需 Azure SQL／hosting，以 Skillable 為主，Terraform backup 為輔。
- **通常不必預建**：SQL MI、兩台 SQL VM、PostgreSQL、完整 gallery。只有教學設計確實需要 portal comparison 時才開。
- **永遠先看 plan**：因 toggles 全部預設 `true`，不能把「沒有特別指定」理解為低成本。

---

## 4. 貫穿全課的雙路徑與 AI 核心觀念

### 4.1 Local 與 Azure 不是 interchangeable

| 主題 | Local SQL Server 2025 validation | Azure／課程路徑 |
| --- | --- | --- |
| Regex | 已完成執行／feature detection | 仍依 service/version 文件確認 |
| Vector type／exact search | 已執行 `vector` 與 `VECTOR_DISTANCE` | 可搭配 Azure model-generated embeddings |
| External model | `sys.external_models` catalog 存在；未配置 approved endpoint／credential，不做生成 | `CREATE EXTERNAL MODEL` + managed identity |
| REST | `sp_invoke_external_rest_endpoint` surface 可偵測；未配置 endpoint 時不呼叫 | 用 managed identity credential 呼叫 Azure OpenAI |
| Full-Text | 當前 container image 未安裝，M10 truthful skip | AI stack可建立 Full-Text catalog／index |
| ANN | 本機舊 `ALLOW_STALE_VECTOR_INDEX` configuration 不支援，不能宣稱 DiskANN 成功 | 使用當前 Azure SQL 支援的 DiskANN／`VECTOR_SEARCH` syntax |
| DAB | CLI 當前未安裝 | 可於 local 安裝或部署至 Azure supported host |

### 4.2 Model、embedding 與 dimensions

- Embedding model 把 text 映射為固定維度向量；**dimensions 是 schema contract**，不是可任意填寫的數字。
- Repo Azure stack 使用 `text-embedding-3-small` 與 `vector(1536)`。若改模型／設定，既有向量必須重建，column 與 index 也要同步。
- Chunking 解決 token limit 與 retrieval granularity：fixed-size 容易實作；semantic chunking 較能保留語意，但流程與成本較高。
- `CREATE EXTERNAL MODEL` 儲存 endpoint/model metadata；它不把模型下載進 database。
- Azure SQL server managed identity 需取得呼叫 Azure OpenAI 的 RBAC，database scoped credential 使用 `IDENTITY = 'Managed Identity'`。控制面成功不代表 RBAC 已傳播，需處理暫時性 `401`／`403`。

### 4.3 Exact、ANN、Full-Text、Hybrid

| 方法 | 適用情境 | 代價／限制 |
| --- | --- | --- |
| Full-Text | 字詞、詞形、phrase、lexical relevance | 需安裝／建立 catalog 與 index；不理解 embedding semantics |
| `VECTOR_DISTANCE` | exact similarity、較小資料集、品質基準 | 全量計算成本隨資料量增加 |
| DiskANN／`VECTOR_SEARCH` | 大資料量、低延遲 approximate retrieval | 近似結果；syntax／availability 版本敏感 |
| Hybrid + RRF | 同時保留 keyword precision 與 semantic recall | 需兩套 retrieval 與 rank fusion |

最新 Azure SQL query pattern 是：

```sql
SELECT TOP (10) WITH APPROXIMATE
    ...
FROM VECTOR_SEARCH
(
    TABLE = dbo.Documents AS documents,
    COLUMN = Embedding,
    SIMILAR_TO = @QueryVector,
    METRIC = 'cosine'
) AS nearest
ORDER BY nearest.distance;
```

`WITH APPROXIMATE` 屬於 `SELECT TOP`；不要沿用本機舊範例的 `TOP_N = ...` form。Index 仍以當前支援 form 建立：

```sql
CREATE VECTOR INDEX IX_Documents_Embedding
ON dbo.Documents(Embedding)
WITH (METRIC = 'cosine', TYPE = 'DISKANN');
```

本機 `DEMO/M10/local/01-search.sql` 保留舊 syntax 作 feature detection，當 `ALLOW_STALE_VECTOR_INDEX` 或 ANN syntax 不支援時應顯示 skip reason；不要把 skip 改講成成功。

### 4.4 RAG flow 與錯誤處理

1. 將 user question 轉為 embedding。
2. 以 exact、ANN 或 hybrid retrieval 取得 top-K context。
3. 用 `FOR JSON PATH` 組裝可控 context；單一物件需要時才用 `WITHOUT_ARRAY_WRAPPER`。
4. 建立 system/developer instruction 與 user prompt，明確要求只依 context 作答、證據不足要說明。
5. 透過 `sys.sp_invoke_external_rest_endpoint` 呼叫 endpoint。
6. 檢查 return value、HTTP description、response JSON path 與 empty answer；失敗時 `THROW`，不要吞錯或回傳假成功。

---

## 5. 逐模組備課指南

以下每個 module 都在同一個 `AdventureGearAI` 資料庫上進行，透過 dependency-aware hybrid runner（`DEMO/scripts/Invoke-DemoModule.ps1`）執行；runner 會先確保 core bootstrap 存在、依賴圖自動補齊 prerequisite，再對 `AdventureGearAI` 跑該 module 的 `common` + `local` setup，並在 `ops.DemoModuleState` 記錄狀態。已 `Completed` 的 module 會被跳過，加 `-Force` 可重跑。所有「重來」都採 module-scoped reset（只移除該 module objects、保留 canonical core），full reset 才會 drop 單一 `AdventureGearAI`；兩者都不碰 legacy `DP800_Mxx`（僅 manual cleanup candidate，永不自動刪除）。

## M01 — Design and implement database objects with SQL

**學習目標**

- 選擇適當 data type、column、constraint 與 index。
- 說明 temporal、in-memory、ledger、graph、JSON 與 partitioning 的用途。
- 以 access pattern 與資料生命週期驅動 physical design。

**教學敘事／PPT 節奏**

先從「正確 schema 是後續 security、performance、AI 的地基」切入。PPT 依 objectives 展開一般 table design，再比較 specialized tables，最後用 constraints／sequence／partitioning 收斂。Demo cue 後進 Knowledge Check，再轉 Lab。

**關鍵比較**

- Temporal：系統維護 history；不是自行寫 audit trigger。
- Ledger：tamper-evidence；不是資料加密替代品。
- Graph：node／edge relationship query；不是所有 relational join 都應改 graph。
- Partitioning：manageability／elimination；不是自動提升所有 query。

**DEMO 建議順序**

1. 以 hybrid runner 對單一 `AdventureGearAI` 執行：`pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 1`。runner 先確保 core，再依序跑 `common/01-objects.sql` → `local/01-inspect.sql`；已 Completed 時加 `-Force` 重跑。
2. 需要重來（module-scoped reset，不 drop database）：對 `AdventureGearAI` 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M01/reset/reset.sql`，只移除 M01 objects 並把 M01–M11 標記 NotStarted，canonical core 保留；再重跑 runner。

展示 temporal `SYSTEM_TIME`、JSON/index、partition、graph node／edge。Azure SQL core syntax 相近，但 filegroup／storage choice 與 boxed SQL Server 不同。

**Official Lab**

- [Lab 01 — Create database objects](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/01-create-database-objects.html)
- Official lab repo path：`Instructions/Labs/01-create-database-objects.html`

**預期成果**

學員能針對 history、relationship、integrity 與 scale requirement 選對 object，而不是只會建立普通 table。

**Knowledge Check**

1. 自動保留 row history：**Temporal table**，因為 engine 管理 current/history 與 system time。
2. 唯一識別且不可為 NULL：**PRIMARY KEY + NOT NULL**；PK 提供 entity uniqueness。
3. 依 range 將大型資料拆分：**Partitioning**；partition function／scheme 定義 boundary 與 placement。

**常見問題／排錯**

- 「有 index 就一定快？」否；要符合 predicate、join、sort 與 selectivity。
- Temporal history 不是無限免費；需 retention／storage strategy。
- Module-scoped reset 只移除 M01 objects 並保留 canonical core；不改成 wildcard drop，也不碰 legacy `DP800_Mxx`（僅 manual cleanup candidate，永不自動刪除）。

**轉場**

Objects 定義資料形狀；M02 將 reusable behavior 與 access boundary 放進 database。

---

## M02 — Implement programmability objects with SQL

**學習目標**

- 建立 view、stored procedure、scalar／table-valued function 與 trigger。
- 依參數化、side effect、reuse、security boundary 選擇 object。

**教學敘事／PPT 節奏**

從「不要把所有 business rule 複製到每個 client」開始。依 view → procedure → function → trigger 比較責任。現有 repo demo 實作 inline TVF 與 `AFTER UPDATE` trigger；multi-statement TVF 與 `INSTEAD OF` trigger 以 PPT walkthrough 比較，不宣稱現有腳本會建立它們。最後進入 KC／Lab。

**關鍵比較**

- View：封裝 query／column exposure，不接受一般參數。
- Stored procedure：可改資料、控制 transaction／error，適合 command。
- TVF：可參數化並回傳 rowset；inline TVF 通常較容易最佳化。
- Trigger：對事件自動反應，但 hidden side effect 要節制。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 2`。runner 確保 core（及需要時的 M01 prerequisite），再跑 `common/01-programmability.sql` → `local/01-exercise.sql`；加 `-Force` 重跑。local exercise 以可 rollback 的 transaction 包住，canonical sales 資料不變。
2. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M02/reset/reset.sql`（只移除 M02 objects，canonical core 保留）。

`01-programmability.sql` 建立 view、stored procedure、scalar function、inline TVF 與 `AFTER UPDATE` audit trigger。講解 multi-statement TVF／`INSTEAD OF` trigger 時回到 PPT syntax 與選型比較，不將其列為 runtime 驗證結果。Local 與 Azure SQL 的 core objects 大致相同；授課時強調 permission／deployment context 仍可能不同。

**Official Lab**

- [Lab 02 — Implement programmability objects](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/02-implement-programmability-objects.html)
- Official lab repo path：`Instructions/Labs/02-implement-programmability-objects.html`

**預期成果**

學員能用明確介面封裝 data access／business logic，並避免濫用 trigger 或 scalar function。

**Knowledge Check**

1. 簡化 complex join 並限制 columns：**View**。
2. Procedure 相較 inline T-SQL：可集中 transaction、permission、error handling，且能重複使用 execution plan。
3. 需要參數化 dynamic filtering：**TVF**，因 view 無一般輸入參數。

**常見問題／排錯**

- Trigger 必須處理 multi-row `inserted`／`deleted`，不能假設一次一列。
- Multi-statement TVF 可能造成 cardinality／optimization 問題。
- Demo 重跑前確認 setup 的 idempotent behavior；必要時對 `AdventureGearAI` 執行該 module 的 scoped reset，不 drop database。

**轉場**

有了 reusable objects，M03 進入較複雜的 analytical、hierarchical、JSON 與 error-handling query。

---

## M03 — Write advanced T-SQL code

**學習目標**

- 使用 CTE／recursive CTE、window functions、JSON、graph `MATCH`、fuzzy／regex。
- 使用 `TRY...CATCH` 保持 transaction 與錯誤行為可預期。

**教學敘事／PPT 節奏**

先以 hierarchy 與 running total 說明「保留 row detail 的 set-based analysis」，再切 JSON／graph／string matching，最後以可靠執行與 error handling 收尾。Speaker notes cue 適合用 recursive CTE、`ROW_NUMBER()`、`FOR JSON PATH`／`OPENJSON` 與 graph `MATCH` 串成短 demo。

**關鍵比較**

- CTE 提升可讀性；recursive CTE 解 hierarchy，但要考慮終止條件與 `MAXRECURSION`。
- Window function 不會像 `GROUP BY` 一樣折疊 row。
- `SOUNDEX`／`DIFFERENCE` 是 phonetic fuzzy；regex 是 pattern；用途不同。
- JSON 是半結構資料，不等於放棄 schema／validation。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 3`。runner 確保 core（及需要時的 M01 prerequisite），再跑 `common/01-advanced-objects.sql` → `local/01-advanced-queries.sql`；加 `-Force` 重跑。
2. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M03/reset/reset.sql`（只移除 M03 objects，canonical core 保留）。

本機已完成 regex feature detection；仍讓 script 報告實際 engine 結果，不硬編版本結論。

**Official Lab**

- [Lab 03 — Write advanced T-SQL](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/03-write-advanced-tsql-code.html)
- Official lab repo path：`Instructions/Labs/03-write-advanced-tsql-code.html`

**預期成果**

學員能以 set-based T-SQL 處理 hierarchy、ranking、semi-structured data 與可診斷錯誤。

**Knowledge Check**

1. 保留每日 row 並計算 running total：`SUM(...) OVER (ORDER BY ...)`。
2. 每位 customer 的 related order items JSON array：`FOR JSON PATH`／適用時 `JSON_ARRAYAGG`。
3. Graph pattern query：`MATCH` operator。

**常見問題／排錯**

- Recursive CTE 無正確 anchor／termination 會無限展開。
- Window `ORDER BY` ties 需 deterministic tie-breaker。
- `TRY...CATCH` 內要檢查 transaction state；catch 不是忽略錯誤。

**轉場**

M03 展示人寫的 advanced SQL；M04 討論 AI 如何協助產生／解釋，但仍需人審核。

---

## M04 — Implement SQL solutions by using AI-assisted tools

**學習目標**

- 使用 GitHub Copilot／supported Fabric experiences 協助 SQL development。
- 設定 repository instructions 與 MCP context。
- 評估 generated SQL 的 correctness、security 與 data exposure。

**教學敘事／PPT 節奏**

先展示 AI assistant 的角色，再談 security impact；接著從 prompt／explain／review 進到 `.github/copilot-instructions.md` 與 MCP tool context。不要把 live model 回答當固定教材；以 poor SQL → review → reference improvement 的可比較流程授課。

**關鍵比較**

- Copilot suggestion 是候選實作，不是 authoritative answer。
- Repository instructions 提供 project conventions；不能替代 database metadata、tests 或 review。
- MCP 提供 structured tool context；不是讓 model 自動取得所有 production 權限。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 4`。runner 對 `AdventureGearAI` 跑兩支 read-only 的 `local/01-review-target.sql` 與 `local/02-reference-improvement.sql`（idempotent，資料不變）。
2. 以 `DEMO/M04/common/copilot-instructions-example.md` 為可審查 instruction，透過 approved Copilot tool explain／review／refactor，再對照 `local/02-reference-improvement.sql`。
3. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M04/reset/reset.sql`。

Local 可做 offline review exercise；official Lab 需要 Azure SQL Database。Fabric Copilot 是 cloud-only supported experience。

**Official Lab**

- [Lab 04 — AI-assisted tools](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/04-design-implement-sql-solutions-ai-assisted-tools.html)
- Official lab repo path：`Instructions/Labs/04-design-implement-sql-solutions-ai-assisted-tools.html`

**預期成果**

學員能安全提供 context、要求解釋與改善，並以 execution plan、tests、docs 與 code review 驗證答案。

**Knowledge Check**

1. SSMS 的 AI assistance：**GitHub Copilot through the supported AI Assistance workload／experience**。
2. Credential 做法：**environment／approved secret store，絕不貼入 prompt**。
3. MCP 差異：提供 structured tools／context，而非只有自然語言 completion。

**常見問題／排錯**

- 不把 schema dump、customer rows、connection string 貼進 chat。
- Model output 每次可能不同，Demo 成功標準是 review process，不是逐字相同。
- MCP permission 應 least privilege；tool available 不等於 tool authorized。

**轉場**

AI-assisted development 放大生產力，也放大風險；M05 進入資料與 endpoint security。

---

## M05 — Implement data security and compliance with SQL

**學習目標**

- 比較 Always Encrypted、TDE、DDM、RLS 與 object permission。
- 說明 Entra authentication、auditing 與 model／API endpoint protection。

**教學敘事／PPT 節奏**

以「資料在 rest、in use、query result、row scope、identity」五個層次拆解。先 encryption，再 masking／RLS／permission，最後接 Azure identity、auditing 與 AI endpoint。Demo 只執行安全可重設的 DDM／RLS；TDE／Always Encrypted 說明 boundary。

**關鍵比較**

- TDE：保護 data／log／backup at rest；有權 query 的使用者仍看到 plaintext。
- Always Encrypted：由 configured client driver 加解密，可隔離 DBA；deterministic 支援 equality pattern，但洩漏相等性。
- DDM：顯示層遮罩，不是 encryption／authorization。
- RLS：依 predicate 過濾 rows；需防止 side-channel 與錯誤 predicate。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 5`。runner 對 `AdventureGearAI` 跑 `common/01-security.sql` → `local/01-verify-security.sql`；demo users 每次 drop/recreate，加 `-Force` 安全。
2. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M05/reset/reset.sql`（只移除 `security` schema 的 module objects，canonical `customer.Customers` 保留）。

Local 執行 DDM／RLS；TDE 僅檢視，不以 hardcoded master-key password 自動化；Always Encrypted 需 configured client driver。Entra／Log Analytics auditing 為 Azure path。

**Official Lab**

- [Lab 05 — Security compliance](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/05-implement-security-compliance.html)
- Official lab repo path：`Instructions/Labs/05-implement-security-compliance.html`

**預期成果**

學員能依 threat／data state 選擇 control，理解 masking 不等於 encryption、TDE 不等於 column confidentiality。

**Knowledge Check**

1. Credit card equality search 且 DBA 不可讀：**Always Encrypted deterministic**。
2. 只顯示末四碼：**Dynamic Data Masking custom function**。
3. TDE vs Always Encrypted：前者保護 at-rest files；後者保護 selected columns 並由 client driver 解密。

**常見問題／排錯**

- `UNMASK`／高權限使用者可能看到原值；DDM 不是 security boundary 的唯一層。
- RLS predicate function 要 schema binding／正確 permission design。
- Azure SQL Entra admin、database user 與 RBAC 是不同層次。

**轉場**

安全 controls 建好後，M06 看 workload 在 concurrency 與 service tier 下是否穩定。

---

## M06 — Optimize database performance

**學習目標**

- 比較 Azure SQL General Purpose、Business Critical、Hyperscale。
- 使用 execution plan、DMV、Query Store 診斷 query。
- 說明 isolation、blocking、deadlock、plan regression 與 forcing。

**教學敘事／PPT 節奏**

先從 platform tier／latency requirement，進到 isolation 與 concurrency，再用 estimated／actual plan、DMV、Query Store 形成 diagnosis loop。最後用 blocking／deadlock live demo 強調「等待關係」而非只背名詞。

**關鍵比較**

- Estimated plan 不執行 query；actual plan 含 runtime observations。
- Blocking 是正常 concurrency 現象，長時間 blocking 才需診斷；deadlock 會選 victim。
- Query Store 保存歷史；DMV 常反映目前／自上次啟動的狀態。
- Plan forcing 是 mitigation，不是免除 root-cause analysis。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 6`。runner 對 `AdventureGearAI` 跑 `common/01-workload.sql` → `local/01-plans-query-store-dmvs.sql`。
2. Blocking／deadlock 為互動式、需多個同時 session，故意排除於 runner manifest 之外；手動對 `AdventureGearAI` 執行：
   - Blocking：三個獨立 session，依序準備 `local/02-blocker.sql`、`local/03-blocked.sql`、`local/04-observe-blocking.sql`。
   - Deadlock：兩個獨立 session，協調同時執行 `local/05-deadlock-session-a.sql`、`local/06-deadlock-session-b.sql`。
3. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M06/reset/reset.sql`。

**Query Store regression／plan forcing walkthrough**

現有 `01-plans-query-store-dmvs.sql` 會啟用並查詢 Query Store，但不會刻意製造 parameter sniffing regression 或自動 force plan。若目標資料庫已收集同一 query 的多個 plans，使用以下查詢選擇 `query_id`／`plan_id`，再由講師明確執行 force／unforce：

```sql
SELECT
    queryText.query_sql_text,
    queryEntry.query_id,
    planEntry.plan_id,
    planEntry.is_forced_plan,
    runtimeStats.avg_duration,
    runtimeStats.count_executions
FROM sys.query_store_query_text AS queryText
INNER JOIN sys.query_store_query AS queryEntry
    ON queryEntry.query_text_id = queryText.query_text_id
INNER JOIN sys.query_store_plan AS planEntry
    ON planEntry.query_id = queryEntry.query_id
INNER JOIN sys.query_store_runtime_stats AS runtimeStats
    ON runtimeStats.plan_id = planEntry.plan_id
ORDER BY runtimeStats.avg_duration DESC;

EXEC sys.sp_query_store_force_plan
    @query_id = <QUERY_ID>,
    @plan_id = <KNOWN_GOOD_PLAN_ID>;

EXEC sys.sp_query_store_unforce_plan
    @query_id = <QUERY_ID>,
    @plan_id = <KNOWN_GOOD_PLAN_ID>;
```

`<QUERY_ID>` 與 `<KNOWN_GOOD_PLAN_ID>` 必須取自當次 Query Store 結果，不可硬編碼到 repo。若只有一個 plan，將 parameter sniffing／regression 當作 PPT walkthrough，不捏造 forcing 成功。

**安全／協調**

- Blocking／deadlock scripts 故意互相等待，不能 unattended sequential run。
- 開始前指定 session A／B／observer，先說明預期誰會 block／victim。
- 結束後 rollback／關閉 transaction；若狀態不明，對 `AdventureGearAI` 執行 M06 scoped reset（只移除 M06 objects），不 drop database。

**Official Lab**

- [Lab 06 — Optimize database performance](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/06-optimize-database-performance.html)
- Official lab repo path：`Instructions/Labs/06-optimize-database-performance.html`

**預期成果**

學員能用 evidence 建立「症狀 → plan／wait → root cause → mitigation → validation」流程。

**Knowledge Check**

1. 低 I/O latency 且含 read-only replica：**Business Critical**。
2. Azure SQL 預設 row-versioning read committed behavior：**RCSI**。
3. 無 code change 修復 plan regression：**Query Store plan forcing／automatic plan correction**。

**常見問題／排錯**

- Missing-index suggestion 是候選，不可直接全部建立。
- Parameter sniffing 不是所有 bad plan 的原因。
- Query Performance Insight／service tier 是 Azure portal／platform path，本機不會出現。

**轉場**

找到正確修正後，M07 把 schema change 納入 source control 與 repeatable delivery。

---

## M07 — Implement CI/CD by using SQL database projects

**學習目標**

- 建立 SDK-style SQL project、object-per-file source model。
- 以 build、schema compare／SqlPackage、pipeline 驗證與部署。
- 管理 schema drift、branch／PR、pre／post-deployment data。

**教學敘事／PPT 節奏**

從「database 也應像 application code 一樣可建置」切入。展示 object-per-file diff、`dotnet build`，再比較 desired model 與 drift，最後帶到 GitHub Actions／Azure DevOps 與 tests。

**關鍵比較**

- Project model 是 desired state；production hotfix 會造成 drift。
- `.dacpac` 是 build artifact；不是 database backup。
- Pre／post-deployment script 適合 reference data／特定 deployment work，不應變成無限累積 migration dump。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 7`。runner 對 `AdventureGearAI` 跑 idempotent 的 `common/01-inventory-deployment-log.sql`（建立 `catalog.InventoryChangeLog`、`catalog.usp_LogInventoryChange`、`ops.DeploymentLog`）。
2. SQL project **build** 另行示範：執行 `DEMO/M07/local/Build-SqlProject.ps1` 產生針對 `AdventureGearAI` 的 `.dacpac`，檢視 object-per-file diff（0 warnings／0 errors）。
3. 說明 passwordless Entra **publish** profile `DEMO/M07/common/Dp800.Database/DP800.publish.xml`（scoped 到 `AdventureGearAI`）與 sample workflow `DEMO/M07/azure/build-deploy.yml`（僅引用 secrets／OIDC，不含 secret value）。
4. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M07/reset/reset.sql`。

Local 可 build／選擇性 publish；Azure workflow 僅引用 secrets／OIDC，不含 secret value。

**Schema drift／DeployReport walkthrough**

現有 `Build-SqlProject.ps1` 只負責 `dotnet build`，不會自動連線 target database。要產生不套用變更的 deployment report，先對測試資料庫做一個受控 hotfix，再使用 Microsoft Entra interactive authentication：

```powershell
$dacpac = Resolve-Path '.\DEMO\M07\common\Dp800.Database\bin\Debug\Dp800.Database.dacpac'
$report = Join-Path $env:TEMP 'dp800-deploy-report.xml'

SqlPackage `
  /Action:DeployReport `
  /SourceFile:"$dacpac" `
  /TargetConnectionString:"Server=tcp:<server>.database.windows.net,1433;Initial Catalog=<database>;Authentication=Active Directory Interactive;Encrypt=True;TrustServerCertificate=False" `
  /OutputPath:"$report"
```

開啟 report，找出 target 與 project model 的 `Create`／`Alter`／`Drop` actions。這是 review artifact，不會部署；確認內容後才可執行 Publish。不得把 SQL password 或 access token 寫進 command、publish profile 或 repo。

**Official Lab**

- [Lab 07 — CI/CD SQL database projects](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/07-implement-cicd-sql-database-projects.html)
- Official lab repo path：`Instructions/Labs/07-implement-cicd-sql-database-projects.html`

**預期成果**

學員能將 schema 變更變成可 review、可 build、可驗證、可部署的 artifact。

**Knowledge Check**

1. Production hotfix 使 project 不同步：**Schema drift**，用 schema comparison／deploy report 偵測。
2. GitHub Action deploy `.dacpac`：**`Azure/sql-action`**。
3. Pre／post-deployment：處理 deployment 前後必要工作；不同於每版手寫 migration chain。

**常見問題／排錯**

- Build success 不代表 deploy 無 destructive change；仍需 deploy report／review。
- Pipeline identity 要 least privilege，避免 username／password 長期 secret。
- Reference data 要考慮 idempotency。

**轉場**

CI/CD 解決 database delivery；M08 將 database 安全地暴露給 application 與 Azure services。

---

## M08 — Integrate SQL solutions with Azure services

**學習目標**

- 用 Data API Builder 設定 REST／GraphQL entity、field、relationship、permission。
- 以 `@env()` 引用 connection string。
- 說明 Azure hosting、monitoring、CDC／event-driven integration。

**教學敘事／PPT 節奏**

先從「不要為每個 CRUD endpoint 手寫 boilerplate」切入，展示 `dab-config.json` 與 entity permission，再比較 REST／GraphQL。最後補 hosting、Application Insights／Log Analytics、CDC／Functions。

**關鍵比較**

- REST：resource-oriented endpoint；GraphQL：client 選欄位與關聯。
- DAB 產生 data API，不取代 database permission／application authorization design。
- Connection string 應由 environment／hosting secret configuration 注入。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 8`。runner 對 `AdventureGearAI` 跑 `common/01-product-api.sql`，建立 read-only `api.Categories`／`api.Products`／`api.ProductCatalog`／`api.InventoryAvailability` views。
2. 檢視 `DEMO/M08/common/dab-config.json`；依 `DEMO/M08/local/README.md` 由 `DATABASE_CONNECTION_STRING` 環境變數注入連線字串。
3. 若已安裝 DAB CLI：`dab start --config DEMO/M08/common/dab-config.json`；若 CLI 仍 absent：只做 config walkthrough，改由 official Lab 操作。
4. Azure hosting differences：`DEMO/M08/azure/README.md`（managed identity）。
5. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M08/reset/reset.sql`。

Local 使用 SQL authentication 僅為 trainer convenience；Azure hosting 應使用 Entra／managed identity。

**Official Lab**

- [Lab 08 — Integrate SQL with Azure services](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/08-integrate-sql-solutions-azure-services.html)
- Official lab repo path：`Instructions/Labs/08-integrate-sql-solutions-azure-services.html`

**預期成果**

學員能建立不含 hardcoded connection string、具最小 permission 的 REST／GraphQL data API。

**Knowledge Check**

1. 不在 config hardcode connection string：使用 **`@env()`**。
2. Read-only entity：permissions 只允許 **`read`**。
3. REST vs GraphQL：REST 依 resource／route；GraphQL 由 query schema 選取 fields／relationships。

**常見問題／排錯**

- 本機 validation 的 DAB CLI 目前 absent；不要到課堂才發現 `dab` command 不存在。
- `@env()` 只避免值寫入 config；仍需保護 process／hosting environment。
- API 能啟動不代表 authorization 正確，要測未授權 write。

**轉場**

M08 讓 application 使用資料；M09 開始讓 database 使用 model endpoint 產生 embedding。

---

## M09 — Design and implement models and embeddings with SQL

**學習目標**

- 評估 model／endpoint 並建立 `CREATE EXTERNAL MODEL` metadata。
- 選擇 chunking strategy，產生、儲存、更新 embeddings。
- 理解 model dimensions、credential、RBAC 與 endpoint lifecycle。

**教學敘事／PPT 節奏**

先問「SQL 如何知道要呼叫哪個 embedding model？」引出 external model；再從 text → chunks → embeddings → `vector(n)` → refresh strategy。Demo 先 local feature detection，再展示 Azure managed-identity template，避免把 catalog 存在誤說成已完成 live embedding。

**關鍵比較**

- External model 是 endpoint metadata，不是 model binary。
- Fixed-size chunking 簡單；semantic chunking 保留段落意義。
- Embedding model 與 chat model 工作不同；embedding 不直接產生自然語言答案。
- 1536 dimensions 是目前 repo model contract，不是所有 embedding model 通用值。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 9`。runner 依賴圖先確保 M01，再對 `AdventureGearAI` 跑 `common/01-review-data.sql`（由 `customer.ProductReviews` join `catalog.Products` 建 `ai.EmbeddingDocuments`）→ `local/01-feature-detection.sql`。
2. 解讀已驗證結果：`vector` 與 external-model catalog 可用；沒有 approved endpoint／credential 時 **external model／embedding generation** 正確地 skip。
3. Walkthrough Azure managed-identity template `DEMO/M09/azure/01-external-model.sql`（`AdventureGearEmbeddingModel`）；完整 backup implementation 見 `TERRAFORM/sample-data/ecommerce-ai.sql`。SQLCMD variables 必須 runtime supplied，檔案不得放 key／token。
4. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M09/reset/reset.sql`。

Azure template 的 SQLCMD variables 必須 runtime supplied；credential 另以 managed identity 建立，檔案不得放 API key。

**Official Lab**

- [Lab 09 — Generate and update embeddings](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/09-generate-update-embedings-sql.html)
- Official lab repo path：`Instructions/Labs/09-generate-update-embedings-sql.html`
- 檔名 `embedings` 是官方 repo 既有拼字，不要自行修正 URL。

**預期成果**

學員能把 model endpoint 安全地註冊到 SQL，選擇正確 dimension，並設計 embedding initial load／refresh。

**Knowledge Check**

1. External model definition：**儲存 AI endpoint/model metadata 的 database object**。
2. Chunking purpose：把大型內容切成符合 token limit 且可有效 retrieval 的片段。
3. Embedding storage：**`vector`**，不是 `nvarchar(max)`。

**常見問題／排錯**

- `sys.external_models` 存在不代表 endpoint、RBAC、quota 或 generation 已成功。
- Dimension mismatch 會造成 cast／insert／index 問題；換 model 要重建 embeddings。
- Managed identity `401`／`403` 可能是 RBAC propagation；要 retry，但不能無限吞錯。
- SQL Server 2025 與 Azure SQL Managed Instance 的 external REST endpoint 預設停用；需由具 `ALTER SETTINGS` 的管理者先執行：

  ```sql
  EXEC sp_configure 'external rest endpoint enabled', 1;
  RECONFIGURE WITH OVERRIDE;
  ```

  Azure SQL Database 預設啟用。此 server-level 設定與 database-level `EXECUTE ANY EXTERNAL ENDPOINT` permission 是不同層次；`AI_GENERATE_EMBEDDINGS` 呼叫 external model endpoint 時也依賴可用的外部 REST 能力。
- 不宣稱目前 Azure apply 已通過。

**轉場**

M09 已將語意轉為向量；M10 比較如何以 keyword、exact vector、ANN 與 hybrid 找回內容。

---

## M10 — Design and implement intelligent search with SQL

**學習目標**

- 使用 `CONTAINS`／`FREETEXT` 與 Full-Text ranking。
- 比較 `VECTOR_DISTANCE` exact search 與 `VECTOR_SEARCH` ANN。
- 以 Reciprocal Rank Fusion（RRF）組合 keyword 與 vector ranking。

**教學敘事／PPT 節奏**

先用「找出含 run 的詞形」建立 lexical search，再用「意思相近但字不同」引出 vector。接著用小資料 exact baseline，再說明 500K rows 等規模為何需要 ANN。最後用 RRF 表達 hybrid 不必先把兩種 score 正規化成同一尺度。

**關鍵比較**

- `CONTAINS` 可精確指定 phrase／prefix／`FORMSOF(INFLECTIONAL)`；`FREETEXT` 較自然語言化。
- Cosine similarity 常見範圍為 -1 到 1；cosine distance = `1 - similarity`，範圍 0 到 2，越小越近。
- Exact search 品質可作 ANN 基準；ANN 以 recall 換 latency／scale。
- RRF 使用 rank，不直接相加不可比較的 raw scores。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 10`。runner 依賴圖 resolve M01 → M09 → M10，再對 `AdventureGearAI` 跑 `common/01-search-data.sql`（由 reviews join products 建 `search.SearchDocuments`，展開成 100+ vectorized documents）→ `local/01-search.sql`。
2. 解讀本機結果：
   - Full-Text 因 image 未安裝而 skip；
   - exact `VECTOR_DISTANCE` 可執行；
   - 本機缺 **vector index** surface／舊 ANN configuration 不支援時，ANN truthful skip；
   - hybrid 因 Full-Text 不可用而 skip。
3. 對照 Azure current syntax：`DEMO/M10/azure/01-ann-search.sql` 僅是 guarded template；實際 AI stack current query 見 `TERRAFORM/sample-data/ecommerce-ai.sql`。
4. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M10/reset/reset.sql`。

授課時明確指出：舊 local script 的 `TOP_N` syntax 是 compatibility probe；最新 Azure SQL path 使用 `SELECT TOP (...) WITH APPROXIMATE` 並省略 `TOP_N`。

**Official Lab**

- [Lab 10 — Implement intelligent search](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/10-implement-intelligent-search.html)
- Official lab repo path：`Instructions/Labs/10-implement-intelligent-search.html`

**預期成果**

學員能依 data scale／quality／latency 選 exact 或 ANN，並用 Full-Text + vector + RRF 建立 hybrid retrieval。

**Knowledge Check**

1. 找 `run` 的詞形：`CONTAINS(..., 'FORMSOF(INFLECTIONAL, run)')`。
2. Cosine distance range：**0–2**；越小越相近。
3. 500K rows 且 speed 優先：**`VECTOR_SEARCH` ANN**。

**常見問題／排錯**

- Full-Text absent 是 image packaging 問題，不代表 SQL Server 2025 產品永遠不支援。
- ANN skip 不能以 exact result 代替並宣稱 ANN 成功。
- `WITH APPROXIMATE` 放在 `SELECT TOP`，不是 `CREATE VECTOR INDEX` option。
- Preview／GA 與 syntax 會變；delivery day 重查官方頁面。

**轉場**

M10 解決 retrieval；M11 把 retrieved context 放進 prompt，並可靠地處理 generation endpoint。

---

## M11 — Design and implement RAG with SQL

**學習目標**

- 說明 RAG 與 fine-tuning 的差異。
- 用 SQL 完成 retrieval、context JSON、prompt、REST invocation 與 response parsing。
- 保護 endpoint credential，處理 HTTP／payload／empty response error。

**教學敘事／PPT 節奏**

以「LLM 不知道今天 database 裡的 product review」說明 grounding need。依 retrieval → augmentation → generation 三段帶完整 stored procedure。先 local 建 prompt，再看 Azure managed-identity REST；最後故意討論 failure path，而不只 happy path。

**關鍵比較**

- RAG 在 query time 注入 current data，不需重新訓練 model。
- Fine-tuning 改變 model behavior／style，不是頻繁更新 factual data 的首選。
- `FOR JSON PATH` 適合多筆 context；`WITHOUT_ARRAY_WRAPPER` 只在確定單一 JSON object 時使用。
- Database scoped credential 保護 endpoint access；仍需限制 `EXECUTE ANY EXTERNAL ENDPOINT`。

**DEMO 建議順序**

1. 執行 `pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 11`。runner 依賴圖 resolve M01 → M09 → M10 → M11，`search.SearchDocuments` 先備妥；再對 `AdventureGearAI` 跑 `common/01-local-rag.sql`（建 `ai.usp_BuildRagPrompt`）→ `local/01-build-prompt.sql`。
2. 說明 local 已偵測 REST procedure surface，但沒有 approved endpoint／credential 時只建 context／prompt，不做 generation。
3. Walkthrough Azure managed-identity **REST** pattern `DEMO/M11/azure/01-rag-procedure.sql`（`ai.usp_AskProductQuestion`）；完整 error-handling implementation 見 `TERRAFORM/sample-data/ecommerce-ai.sql`。
4. 需要重來：對 `AdventureGearAI` 執行 module-scoped reset `pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M11/reset/reset.sql`。

Azure path 應檢查 return value、HTTP description、JSON response path 與 empty answer；managed identity／RBAC failure 不可被包成空字串。

SQL Server 2025／Azure SQL Managed Instance 在執行本段前，必須先由具 `ALTER SETTINGS` 的管理者啟用：

```sql
EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
```

Azure SQL Database 預設啟用；所有平台仍需 database-level `EXECUTE ANY EXTERNAL ENDPOINT` 與正確 credential／identity。

**Official Lab**

- [Lab 11 — Implement RAG solutions](https://microsoftlearning.github.io/mslearn-sql-developer/Instructions/Labs/11-implement-rag-solutions.html)
- Official lab repo path：`Instructions/Labs/11-implement-rag-solutions.html`

**預期成果**

學員能說明並追蹤完整 RAG data flow，知道 retrieval quality、prompt grounding、identity 與 endpoint reliability 都會影響答案。

**Knowledge Check**

1. RAG 相對 fine-tuning 的優點：**query time 使用目前資料，不需 retrain**。
2. 單一 JSON object 去除外層 brackets：**`WITHOUT_ARRAY_WRAPPER`**。
3. 呼叫 external REST endpoint 的 permission：**`EXECUTE ANY EXTERNAL ENDPOINT`**。

**常見問題／排錯**

- Retrieval 無結果時 context 應為 `[]`／明確 insufficient evidence，不要讓 model 猜。
- HTTP success 仍可能有 unexpected payload；要驗證 JSON path 與 answer。
- `401`／`403`：檢查 SQL server identity、RBAC、credential URI 與 propagation。
- `429`／quota：降低 concurrency／batch、等待或改用已驗證 capacity；不要現場臨時換 dimension 不同的 embedding model。
- 不宣稱 Azure live RAG smoke test 已通過。

**轉場**

回到全課主線：可靠 schema 與 code → secure／observable delivery → grounded AI retrieval and generation。

---

## 6. Demo reset、recovery 與安全規則

### 6.1 Reset 邊界

- Bootstrap 只建立**單一** `AdventureGearAI` 資料庫（含 8 個 domain schema、`ops.DemoEnvironment` marker、`ops.DemoModuleState` 與 canonical seed）；不建立 per-module 資料庫。
- 每個 module 的 `reset/reset.sql` 是 module-scoped reset：只移除該 module 擁有的 objects、把該 module 與其 dependents 標記 NotStarted，canonical `catalog`／`sales`／`customer` core 保留；它**永不 drop database**。
- 只有 `DEMO/reset/reset-adventuregear.sql`（由 `DEMO/reset/Reset-AdventureGearAI.ps1` 呼叫）可 drop database，且 hard-scoped 到 literal `AdventureGearAI`，drop 後自動重跑 core bootstrap。
- Module-scoped reset 與所有 module 執行都對 `AdventureGearAI`（透過 `DEMO/scripts/Invoke-Dp800Sql.ps1` 的 read-only database guard）執行，不從 per-module 資料庫執行。
- 不修改 script 讓它處理 `AdventureGearAI` 以外的 database、不使用 wildcard drop、不碰 legacy `DP800_Mxx`（僅 manual cleanup candidate，永不自動刪除）。

### 6.2 Idempotency

- Demo 前至少完整跑一次：core bootstrap → runner 執行 module → module-scoped reset → 重跑 runner，確認狀態回到乾淨基線。
- 若 object 已存在，應由 script 的 guarded／drop-create logic 處理；不要現場手動刪除不相關 object。
- Azure data-plane rerun 使用 repo 已設計的 Terraform replacement／script flow，不以 portal 零散修補後假裝 desired state 一致。

### 6.3 Password／secret acquisition

- Local SQL password：process environment 或 secure prompt。
- Terraform `admin_password`：只在 password-based gallery 啟用時，以 secure prompt 放入 `TF_VAR_admin_password`，完成後清除。
- Azure AI：Entra token + managed identity + RBAC；不使用／展示 API key。
- 不在 terminal argument、`.tfvars`、`.env`、plan、log、screenshot、recording、prompt 或 Git 保存 secret。

### 6.4 M06 recovery

- Blocking demo 前先保留 observer session；若卡住，先辨識 session／transaction，再 rollback 指定 session。
- Deadlock 由 engine 選 victim；捕捉錯誤後確認另一 session transaction 已完成／rollback。
- 不用 name-based process kill；不要因 demo 卡住而重啟整個共享 SQL container。
- 最後才對 `AdventureGearAI` 執行 M06 scoped reset（只移除 M06 objects），不 drop database、不碰其他 module 的 objects。

---

## 7. 課程收尾、credential 與清理

### 7.1 End-of-course recap

用一條完整故事線回顧：

1. M01–M03：建立可查詢、可封裝、可分析的 SQL foundation。
2. M04：AI 可協助開發，但必須有 context、review 與安全界線。
3. M05–M08：把 solution 變得 secure、fast、deployable、integrated。
4. M09–M11：model metadata／embedding → exact／ANN／hybrid retrieval → grounded RAG。

### 7.2 Exam／credential positioning

- 本課與 [Microsoft Certified: SQL AI Developer Associate](https://learn.microsoft.com/en-us/credentials/certifications/developing-ai-enabled-database-solutions/) 及 DP-800 exam 相關。
- 可提供 [DP-800 Study Guide](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/dp-800) 作為後續準備入口。
- **不要承諾「上完課即可通過」或「本課涵蓋所有考題」**。考試內容、語言、skills measured 與政策以 delivery day 官方頁面為準。
- 課程頁／Learning Paths 可提供 Achievement Code；它與通過 certification exam 是不同成果。

### 7.3 課後 cleanup／destroy checklist

- [ ] 確認學員已儲存必要 Lab notes，不保存 secret。
- [ ] 停止 local DAB／臨時 process；repo 不停止或刪除外部 `mssql2025` container。
- [ ] 視需要對 `AdventureGearAI` 執行 module-scoped reset，或以 `DEMO/reset/Reset-AdventureGearAI.ps1` 做 full reset；只有這一個資料庫，legacy `DP800_Mxx` 僅為 manual cleanup candidate（永不自動刪除），不由本課流程刪除。
- [ ] 撤除臨時 environment variables、token、connection string。
- [ ] 刪除受保護的 saved Terraform plan。
- [ ] 清點 Azure resource groups、model deployments、SQL、MI、VM、disks、public IP、PostgreSQL、Key Vault、Automation、Database Watcher。
- [ ] 執行並監看 Terraform destroy；MI／VM teardown 可能很久，不要因等待而中斷。
- [ ] 以 Azure portal／CLI 再確認無 orphan resource／billable deployment。
- [ ] 記錄 apply／smoke／destroy 實際結果；沒有證據就維持「未驗證」。
- [ ] 引導完成 [Course Survey](https://aka.ms/dp800survey)。

---

## 8. Known uncertainties 與 delivery-day revalidation

- [ ] **Model lifecycle／quota／capacity**：重新確認 embedding／chat model、版本、deployment type、region 與 subscription quota；歷史 plan 不保留 capacity。
- [ ] **Preview／GA status**：SQL MCP、Database Watcher、vector index／`VECTOR_SEARCH`、SQL AI functions 與 syntax 可能更新。
- [ ] **Azure SQL vector syntax**：重查 `CREATE VECTOR INDEX` 與 `VECTOR_SEARCH` 官方文件；確認仍使用 `SELECT TOP (...) WITH APPROXIMATE` 且不使用舊 `TOP_N`。
- [ ] **Local SQL image**：重跑 regex、vector、external-model catalog、REST、Full-Text、ANN detection；不要假設 image 未變。
- [ ] **DAB CLI**：執行 `dab --version`；若 absent，預先安裝或把 M08 改為 config walkthrough。
- [ ] **Study Guide title bug**：DP-800 Study Guide URL 曾回傳正確內容但 HTML title 顯示 DP-700；delivery day 再檢查是否修正，並提醒學員以頁面內容／URL 為準。
- [ ] **Official pages／Labs changing**：重跑 `python .github/skills/course-prep/scripts/link_check.py docs/link-ledger.txt`；確認 module／lab title、Lab 09 intentional filename 與 final URL。
- [ ] **PPT vs current service**：若 slide model／syntax 與 current docs 不同，以 current official docs 為準，口頭標示教材版本差異。
- [ ] **Exam language／skills measured**：不沿用舊結論；delivery day 查官方 credential／study guide。
- [ ] **Azure backup gate**：只有真實 `apply`、data-plane smoke test、output review、`destroy` 全部成功，才可對學員說 backup environment 已驗證。

---

## 9. 講師小技巧

- 每個 module 開頭先給一個「為什麼」，結尾用 KC 驗證，再以一句 transition 接下一 module。
- Live demo 只改一個變因；先展示預期結果，再展示 failure／skip reason。
- M09–M11 先畫出 model → embedding → retrieval → context → generation，學員較不會把 vector database 與 LLM 混為一談。
- 時間不足時，保留 M06 diagnosis、M09 dimension／identity、M10 exact vs ANN、M11 error handling；縮短 portal navigation。
- Azure 長時間 provisioning、embedding batch 與 model deployment 使用預建環境；課堂 live 做 SQL query／inspection。
- 遇到 preview syntax 差異，不在現場憑記憶改 code；切回已驗證 local path／prepared output，記錄後依官方文件修正。

---

## 10. 參考

- [DP-800 Course](https://learn.microsoft.com/en-us/training/courses/dp-800t00)
- [DP-800 Lab Pages](https://microsoftlearning.github.io/mslearn-sql-developer/)
- [`docs/course-research.md`](./course-research.md)
- [`docs/demo-environment.md`](./demo-environment.md)
- [`DEMO/README.md`](../DEMO/README.md)
- [`TERRAFORM/README.md`](../TERRAFORM/README.md)
