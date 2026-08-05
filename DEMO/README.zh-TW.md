繁體中文 | [English](README.md)

# DP-800 講師示範 — AdventureGearAI 課程流程

此資料夾提供與 11 個 DP-800 模組一致、精簡且可重設的講師示範流程。所有模組現在都針對**一個**資料庫（名稱確實為 `AdventureGearAI`）進行教學，而非使用十一個彼此獨立的 `DP800_Mxx` 資料庫。本機 SQL Server 2025 與 Azure SQL 的行為明確區分，本機容器也一律在此存放庫外部管理。

## AdventureGear AI Commerce 故事

AdventureGear 是一家虛構的戶外裝備零售商。在三天的教學中，課程會逐步建立單一商務資料庫——從核心結構描述與可程式性，延伸至安全性、效能、CI/CD、API 介面，最後是內嵌、智慧搜尋與 RAG。這個故事刻意採累積式設計：第 1 天所建立的產品、客戶、訂單與評論資料列，正是第 3 天 AI 模組擷取與做為基礎的同一批資料。

Bootstrap 會在 `AdventureGearAI` 中佈建八個領域結構描述：

| Schema | 用途 |
|---|---|
| `catalog` | 產品、類別、庫存，以及 M01/M03 物件示範（時間資料表價格、JSON 投影、分割、圖形）。 |
| `sales` | 訂單、訂單項目，以及 M02 可程式性物件（檢視表、預存程序、函式、觸發程序）。 |
| `customer` | 客戶與產品評論——M09/M10/M11 的來源資料列。 |
| `security` | M05 安全投影、動態資料遮罩與資料列層級安全性原則。 |
| `ops` | 操作追蹤（`ops.DemoEnvironment`、`ops.DemoModuleState`）以及 M03/M06 教學物件。 |
| `api` | 透過 Data API Builder (REST/GraphQL) 公開的 M08 唯讀檢視表。 |
| `search` | 由目錄產品與客戶評論建立的 M10 搜尋文件。 |
| `ai` | M09 內嵌文件，以及 M11 RAG 提示與預存程序介面。 |

由 bootstrap 僅建立一次的標準種子資料包含 **10 個 categories、150 個 products、120 個
customers、800 個 orders、2,400 個 order items 和 500 個 reviews**。模組會擴充此核心；
絕不會重新建立它。此決定性資料量分別由固定 seed 維持，功能偵測則由當天的
engine/image 決定：即使 In-Memory OLTP、
Ledger、Sequence、PolyBase、Full-Text Search 或其他已安裝功能不可用，仍能以相同 seed
教授原生 `json` 與 JSON index 操作。

M01 會新增 native JSON、SQL Server 2025 preview JSON index、In-Memory OLTP、Ledger、
Sequence 和 feature-detected PolyBase external metadata。其 reset 會保留 memory-optimized
filegroup/container（移除它可能使 container 停滯），並且 Ledger drop 後可能留下
engine-managed dropped-ledger 資料表；兩者皆為刻意設計。需要 Full-Text Search 或 PolyBase
時，請使用 [custom FTS/PolyBase Docker image](docker/README.md)。

## 本機連線

| 設定 | 值 |
|---|---|
| 容器 | `mssql2025`（在此存放庫外部管理） |
| 位址 | `127.0.0.1:1433`（`sqlcmd` 使用 `127.0.0.1,1433`） |
| 登入 | `sa` |
| 密碼 | `DP800_SQL_PASSWORD`，接著是 `SQLCMDPASSWORD`，否則為安全提示 |

此存放庫絕不建立、啟動、停止、移除或保存該容器。絕不可將 SA 密碼放入指令碼、命令引數、連接字串、`.env` 檔案或 Git 歷程記錄中。

## Bootstrap 與執行模組

需要 PowerShell 7 與 `sqlcmd`。請從存放庫根目錄執行每一個命令，並先設定 `$env:DP800_SQL_PASSWORD`。

### 僅核心 Bootstrap

僅佈建單一 `AdventureGearAI` 資料庫——包括其結構描述、`ops.DemoEnvironment` 標記、`ops.DemoModuleState` 資料列與標準電子商務種子資料——而不執行任何模組：

```powershell
pwsh -NoProfile -File DEMO/bootstrap/Invoke-Bootstrap.ps1
```

### 執行一個、多個或所有模組

模組透過具備相依性感知能力的混合式執行器執行。兩個進入點都會先確保核心存在，然後針對 `AdventureGearAI` 執行每個模組的 `common` + `local` 設定。於 bootstrap 要求模組時，只會委派給同一個執行器：

```powershell
# 單一模組（bootstrap 委派給執行器）：
pwsh -NoProfile -File DEMO/bootstrap/Invoke-Bootstrap.ps1 -Modules 1

# 多個模組（順序無關；相依性會自動解析）：
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 5,6,7

# 依相依性順序執行全部十一個模組：
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1
```

未指定 `-Modules` 的 `Invoke-DemoModule.ps1` 會執行 M01–M11。已是 `Completed` 的模組會略過；加入 `-Force` 可重新執行：

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 2 -Force
```

## 操作追蹤與相依性解析

兩個 `ops` 資料表讓單一資料庫具有自我描述能力並支援等冪執行：

- **`ops.DemoEnvironment`** — 單一標記資料列會將資料庫固定為 `AdventureGearAI`，並記錄示範名稱、結構描述版本與初始化時間。SQL 防護程式（`scripts/Assert-DemoDatabase.sql`）會拒絕在此標記不存在時執行模組或重設指令碼，因此任何具破壞性的作業都無法針對錯誤的資料庫執行。
- **`ops.DemoModuleState`** — 每個模組（M01–M11）各有一列，追蹤 `NotStarted`、`Running`、`Completed` 或 `Failed`。執行器讀取此狀態來略過已完成的模組（除非指定 `-Force`），並記錄每個模組的成功或失敗。

執行器會從相依性圖表自動解析先決條件：

- **累積式 M01 → M11 路徑。** M01 建立於核心之上；M02–M09 建立於 M01 之上；M10 建立於 M01 + M09 之上；M11 建立於 M01 + M09 + M10 之上。要求較晚的模組時，會遞移地先納入並執行其先決條件，且以決定性的拓撲順序執行（模組編號遞增作為平手判定）。例如，`-Modules 11` 會執行 M01 → M09 → M10 → M11，因此 M11 讀取 `search.SearchDocuments` 前，該資料已植入種子。
- **獨立模組路徑。** 僅相依於核心加上 M01 的模組（M02–M08）可依任意順序個別執行；要求其中一個時，會執行核心，接著 M01，最後是該模組。

## 重設工作流程

有兩種重設範圍，兩者都不會卸除 `DP800_Mxx` 資料庫。

### 模組重設（範圍限定）

每個模組都提供 `reset/reset.sql`，它僅移除該模組所擁有的物件，並將該模組——以及每個相依模組——在 `ops.DemoModuleState` 中還原為 `NotStarted`。標準 `catalog`/`sales`/`customer` 核心會保持不變。請針對 `AdventureGearAI` 執行：

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M01/reset/reset.sql
```

因為每個模組都遞移地相依於 M01，重設 M01 會將 M02–M11 標記為過期，讓執行器能以乾淨的基準重新套用它們。

### 完整重設（資料庫層級）

唯一獲准卸除資料庫的指令碼會嚴格限定於確切的 `AdventureGearAI`。此包裝函式會復原作用中的工作階段、卸除資料庫，然後重新執行核心 bootstrap：

```powershell
pwsh -NoProfile -File DEMO/reset/Reset-AdventureGearAI.ps1
```

## 舊版 DP800_Mxx 資料庫

此示範的早期版本會為每個模組建立一個名為 `DP800_M01` 至 `DP800_M11` 的舊版資料庫（僅供手動清理的候選項目）。統一示範只擁有 `AdventureGearAI`，絕不建立、變更或卸除這些資料庫。若它們仍因先前執行而存在，bootstrap 僅會透過 `bootstrap/report-legacy-databases.sql` 將其報告為僅供手動清理的候選項目，絕不會自動刪除。只有在您選擇時才可手動移除它們；沒有任何示範命令會以舊版 `DP800_Mxx` 資料庫為目標（僅供手動清理，絕不會自動刪除）。

## 本機與 Azure 矩陣

| 模組 | 本機 SQL Server 2025 | Azure 路徑 |
|---|---|---|
| M01 物件 | `catalog` 上的 native JSON/preview JSON index、時間資料表、In-Memory、Ledger、Sequence、分割、圖形與 feature-detected PolyBase | 相同核心語法；服務層級/儲存體選項不同 |
| M02 可程式性 | `sales` 中的檢視表、預存程序、函式、觸發程序 | 相同核心物件 |
| M03 進階 T-SQL | CTE、視窗、JSON、模糊、圖形、錯誤處理；偵測 regex | Azure SQL 依服務/版本支援記載的 regex 介面 |
| M04 AI 輔助工作流程 | 針對 `sales`/`customer` 的離線提示/審查練習；不相依於 Copilot API | 使用已核准的 Copilot/Fabric 工具與身分識別控制 |
| M05 安全性 | DDM 和 RLS 在 `security` 中執行；檢查/說明 TDE/Always Encrypted | TDE 由平台管理；Entra 和稽核是 Azure 路徑 |
| M06 效能 | Query Store、計畫、DMV；封鎖/死結指令碼為**互動式**，且排除於執行器之外（需在多個工作階段中手動執行） | 服務層級與 Query Performance Insight 僅限 Azure |
| M07 CI/CD | SDK SQL 專案會**建置**目標為 `AdventureGearAI` 的 dacpac；可選的本機**發佈**使用無密碼 Entra 設定檔 | GitHub Actions 範例使用存放庫密碼/OIDC |
| M08 Data API Builder | DAB relationship entity 使用 `catalog.Categories`/`catalog.Products`；`api.ProductCatalog` 與 `api.InventoryAvailability` 仍為獨立 read-model entity，確保庫存資訊可用 | 受控識別與 Azure 裝載會另外記載 |
| M09 模型/內嵌 | 功能偵測 `vector` 與外部模型目錄；沒有已核准端點/認證時，會略過**外部 REST/模型產生** | 受控識別加上 `CREATE EXTERNAL MODEL` 範本 |
| M10 智慧搜尋 | 安裝/支援時提供全文檢索和精確的 `VECTOR_DISTANCE` 示範；當本機組建缺少**向量索引**介面時，會如實略過 ANN | DiskANN/`VECTOR_SEARCH` 需要受支援的 Azure/預覽設定 |
| M11 RAG | 從 `search` 建立擷取內容/提示；**外部 REST** 執行會進行功能偵測，且需要已核准的端點認證 | Azure REST 產生路徑使用受控識別和 Azure SQL |

不受支援或預覽功能必須報告真實的偵測結果。不可將 SQL Server 2025 與 Azure SQL 視為可互換。
