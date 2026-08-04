繁體中文 | [English](README.md)

# M03 — 撰寫進階 T-SQL

模組 3 會針對 **AdventureGearAI** 示範進階查詢技術。自成一體的組織圖教學物件
（`ops.EmployeeHierarchy` 加上圖形節點/邊緣資料表）支援遞迴 CTE 與圖形示範；
視窗函式、JSON 及模糊比對查詢則會在標準 `catalog` 和 `customer` 核心上執行。

## 執行方式

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 3
```

執行器會確保核心（以及在要求時的 M01 必要條件）存在，接著執行
`common/01-advanced-objects.sql`，然後執行 `local/01-advanced-queries.sql`。
請加上 `-Force` 以重新執行 Completed 模組。

## 示範內容

- 遞迴 CTE 組織圖周遊。
- 對目錄產品使用的視窗函式（`ROW_NUMBER`、已分割的 `SUM`）。
- `OPENJSON` 文件分解。
- `SOUNDEX` / `DIFFERENCE` 模糊比對。
- SQL 圖形 `MATCH` 周遊。
- 對客戶電子郵件執行 SQL Server 2025 `REGEXP_LIKE` 的執行階段偵測。
- 具有已回復交易的結構化 `TRY...CATCH` 錯誤處理。

規則運算式支援會因版本而異；指令碼會報告偵測結果，而不假設平台一致。
請參閱 `azure/README.md`。
