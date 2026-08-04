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

## 互動式並行與計畫指令碼（不由執行器執行）

封鎖與死結示範需要多個同時執行的工作階段，並且**刻意排除**於執行器資訊清單之外。
請針對 AdventureGearAI 手動執行：

- 封鎖：開啟三個工作階段，並執行 `local/02-blocker.sql`、
  `local/03-blocked.sql` 和 `local/04-observe-blocking.sql`。
- 死結：同時執行 `local/05-deadlock-session-a.sql` 與
  `local/06-deadlock-session-b.sql`。

隔離/RCSI 比較刻意使用有標記的 disposable database，而不是 AdventureGearAI。先啟動 probe，
再用兩個工作階段執行 `09-isolation-writer.sql` 和 `10-isolation-reader.sql`；接著執行
`11-enable-rcsi.sql` 後重複兩個工作階段的比較，最後以
`12-isolation-rcsi-cleanup.sql` 清除：

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M06/local/07-isolation-rcsi-probe.sql
```

Query Store plan-forcing 示範也必須手動執行，因為它會擷取、force、驗證並 unforce
計畫，同時還原先前的 capture mode：

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M06/local/08-query-store-plan-forcing.sql
```

隔離比較使用 `SET TRANSACTION ISOLATION LEVEL READ COMMITTED`；計畫示範只有在擷取到
合格的計畫後才會呼叫 `sp_query_store_force_plan`。

Local SQL Server 必須在 disposable database 上啟用 RCSI 才能進行第二次比較；Azure SQL
Database 通常使用 row-versioning defaults，但指令碼仍會回報其實際設定。平台差異請參閱
`azure/README.md`。
