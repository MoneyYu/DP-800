繁體中文 | [English](README.md)

# M08 — 將 SQL 與 Azure 服務整合

使用統一執行器，針對 **AdventureGearAI** 佈建 API 介面：

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 8
```

執行器會執行 `common/01-product-api.sql`，它會在正規 `catalog`/`customer` 領域資料上建立唯讀的 `api.Categories`、`api.Products`、`api.ProductCatalog` 及 `api.InventoryAvailability` 檢視表（不會建立重複的 `ApiProducts`/`ApiCategories` 資料表）。`common/dab-config.json` 會透過 REST 與 GraphQL 公開這些檢視表，且只從目前處理序的 `DATABASE_CONNECTION_STRING` 環境變數讀取連接字串；請勿將它保存至設定檔、存放庫或殼層歷程記錄，並保持 API 設定不變。

請參閱 `local/README.md` 了解本機 DAB，以及 `azure/README.md` 了解受控主機差異。
