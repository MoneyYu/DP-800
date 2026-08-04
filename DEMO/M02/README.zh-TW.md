繁體中文 | [English](README.md)

# M02 — 實作可程式化物件

模組 2 會在統一 **AdventureGearAI** 資料庫的 **sales** 網域結構描述中佈建
可程式化物件。它們會操作標準
`sales.Orders` / `sales.OrderItems` / `customer.Customers` / `catalog.Products`
核心。

## 執行方式

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 2
```

執行器會確保核心存在（並在要求時將 M01 視為必要條件），接著執行
`common/01-programmability.sql`，然後執行 `local/01-exercise.sql`。
請加上 `-Force` 以重新執行 Completed 模組。

## 示範內容

- 報表檢視表（`sales.vw_CustomerOrderSummary`）。
- 純量函式（`sales.fn_OrderTotal`）及內嵌 TVF
  （`sales.fn_CustomerOrders`）。
- 具有 `TRY...CATCH` 的交易式預存程序（`sales.usp_AddOrderItem`）。
- 將資料寫入 `sales.OrderStatusAudit` 的 `AFTER UPDATE` 稽核觸發程序
  （`sales.trg_OrderStatusAudit`）。

本機練習會將異動包裝在最後回復的交易中，因此標準銷售資料不會變更，且模組具有
等冪性。這些物件可在 SQL Server 2025 和 Azure SQL 上運作；請參閱
`azure/README.md`。
