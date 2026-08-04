繁體中文 | [English](README.md)

# M01 — 設計及實作資料庫物件

模組 1 會以本課程涵蓋的物件類型，擴充標準 **AdventureGearAI** 商務核心
（`catalog`、`sales`、`customer`）。它不會重新建立核心
`catalog.Products` / `sales.Orders` 實體。

## 執行方式

統一示範會透過具相依性感知的混合式執行器執行；此執行器會先確認
AdventureGearAI 核心存在，再針對 **AdventureGearAI** 執行本模組的 `common` +
`local` 設定：

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 1
```

若要在先前顯示 Completed 的狀態後重新執行，請加上 `-Force`。執行器會依序執行
`common/01-objects.sql`、`common/02-specialized-tables.sql`、
`local/01-inspect.sql` 和 `local/02-inspect-specialized.sql`；全部皆具等冪性。

## 示範內容

- 從 `catalog.Products` 產生的系統版本控制時態價格資料表
  （`catalog.ProductPrice` + `catalog.ProductPriceHistory`）。
- `catalog.Products.MetadataFrame` 上、涵蓋標準 `ProductMetadata` 文件的
  已建立索引計算 JSON 投影。
- 依範圍分割的訂單教學物件（`sales.PartitionedOrders`）。
- 用來建模產品互補關係的 SQL 圖形節點/邊緣資料表
  （`catalog.ProductNode` / `catalog.ProductRelatedTo`）。
- 原生 `json` 資料行、SQL Server 2025 的 `CREATE JSON INDEX` preview 功能，以及
  `JSON_VALUE`、`JSON_PATH_EXISTS`、`JSON_CONTAINS` 和 `.modify()` 操作。
- In-Memory OLTP 快取、可更新的 Ledger 資料表、Sequence 配發資料表，以及記錄為
  教學資料的 constraint 違規。
- 僅限中繼資料的 feature-detected PolyBase External table；不會查詢外部資料或儲存認證。

決定性的課堂 seed 資料量為 **10 個 categories、150 個 products、120 個
customers、800 個 orders、2,400 個 order items 和 500 個 reviews**。資料量分別由固定
seed 維持，功能偵測則由當天的引擎/image 決定：資料列每次都相同，但 In-Memory OLTP、PolyBase 與
Full-Text Search 是否可用，取決於已安裝的引擎/image。

M01 reset 會移除 In-Memory 資料表，但會刻意保留 memory-optimized filegroup/container，
因為移除它可能使 containerized SQL Server 停滯。卸除可更新的 Ledger 可能會保留
engine-managed dropped-ledger 資料表以供驗證；這是預期行為。需要 Full-Text Search
與 PolyBase 示範時，請使用 [custom FTS/PolyBase Docker image](../docker/README.md)。

Azure SQL 支援核心物件，但檔案群組與儲存體決策不同於盒裝 SQL Server；
請參閱 `azure/README.md`。

模組重設（`reset/reset.sql`）保留給後續工作，並非一般執行器路徑的一部分。
舊版 `DP800_Mxx` 資料庫絕不自動刪除；它們只會列報為手動清理候選項目。
