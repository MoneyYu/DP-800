繁體中文 | [English](README.md)

# M08 — 將 SQL 與 Azure 服務整合

使用統一執行器，針對 **AdventureGearAI** 佈建 API 介面：

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 8
```

執行器會執行 `common/01-product-api.sql`，它會在正規 `catalog`/`customer` 領域資料上建立唯讀的 `api.Categories`、`api.Products`、`api.ProductCatalog` 及 `api.InventoryAvailability` 檢視表（不會建立重複的 `ApiProducts`/`ApiCategories` 資料表）。具有 relationship 的 DAB `Category` 與 `Product` entity 會使用正規的 `catalog` 資料表，因為 DAB CLI 會依資料表 metadata 驗證 entity relationships；唯讀 `api` 檢視表仍供 SQL demo 使用。`common/dab-config.json` 只從目前處理序的 `DATABASE_CONNECTION_STRING` 環境變數讀取連接字串；請勿將它保存至設定檔、存放庫或殼層歷程記錄，並保持 API 設定不變。

設定會在平台允許時 feature-detect 並為其擁有的產品 capture 啟用 CDC。DAB 設定示範 cache
設定、entity relationships 和 stored-procedure entity，且不會將 connection string 放入
source control。

請參閱 `local/README.md` 了解本機 DAB，以及 `azure/README.md` 了解受控主機差異。
