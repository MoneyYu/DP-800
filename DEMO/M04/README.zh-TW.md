繁體中文 | [English](README.md)

# M04 — AI 輔助 SQL 工作流程

本模組不會呼叫 Copilot API，也不會建立新的資料庫物件。它提供可檢閱的指示範例，
以及一組在標準 **AdventureGearAI** 銷售/客戶核心上執行的查詢前後對照。

## 執行方式

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 4
```

執行器會針對 AdventureGearAI 執行兩個唯讀本機指令碼：
- `local/01-review-target.sql` — 用於解釋/檢閱/重構練習的刻意不佳輸入。
- `local/02-reference-improvement.sql` — 已檢閱/重構的參考形式。

請使用 `common/copilot-instructions-example.md` 作為可檢閱的指示範例。
請將產生的回答與參考改良版本比較；絕不可將認證或生產資料貼入提示。
請加上 `-Force` 以重新執行。

由於指令碼為唯讀，本模組完全具等冪性，且不會變更 AdventureGearAI 資料。
請參閱 `azure/README.md`。
