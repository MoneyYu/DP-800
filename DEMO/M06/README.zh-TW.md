繁體中文 | [English](README.md)

# M06 — 最佳化資料庫效能

模組 6 會建立可調整的工作負載（`ops.PerformanceOrders`），其衍生自標準
**AdventureGearAI** 目錄/客戶核心，並示範執行計畫、涵蓋索引、Query Store 與 DMV
檢查。

## 執行方式

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 6
```

執行器會針對 AdventureGearAI 執行 `common/01-workload.sql`，然後執行
`local/01-plans-query-store-dmvs.sql`。兩者皆具等冪性；請加上 `-Force` 以重新執行。

## 互動式並行指令碼（不由執行器執行）

封鎖與死結示範需要多個同時執行的工作階段，並且**刻意排除**於執行器資訊清單之外。
請針對 AdventureGearAI 手動執行：

- 封鎖：開啟三個工作階段，並執行 `local/02-blocker.sql`、
  `local/03-blocked.sql` 和 `local/04-observe-blocking.sql`。
- 死結：同時執行 `local/05-deadlock-session-a.sql` 與
  `local/06-deadlock-session-b.sql`。

所有指令碼都以結構描述限定的 `ops.PerformanceOrders` 物件為目標。
如需平台差異，請參閱 `azure/README.md`。
