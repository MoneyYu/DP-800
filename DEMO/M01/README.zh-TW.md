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
`common/01-objects.sql`，然後執行 `local/01-inspect.sql`；兩者皆具等冪性。

## 示範內容

- 從 `catalog.Products` 產生的系統版本控制時態價格資料表
  （`catalog.ProductPrice` + `catalog.ProductPriceHistory`）。
- `catalog.Products.MetadataFrame` 上、涵蓋標準 `ProductMetadata` 文件的
  已建立索引計算 JSON 投影。
- 依範圍分割的訂單教學物件（`sales.PartitionedOrders`）。
- 用來建模產品互補關係的 SQL 圖形節點/邊緣資料表
  （`catalog.ProductNode` / `catalog.ProductRelatedTo`）。

Azure SQL 支援核心物件，但檔案群組與儲存體決策不同於盒裝 SQL Server；
請參閱 `azure/README.md`。

模組重設（`reset/reset.sql`）保留給後續工作，並非一般執行器路徑的一部分。
舊版 `DP800_Mxx` 資料庫絕不自動刪除；它們只會列報為手動清理候選項目。
