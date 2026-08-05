繁體中文 | [English](README.md)

# M07 — 使用 SQL 資料庫專案進行 CI/CD

`common/Dp800.Database` 是 SDK 樣式的 SQL 專案（每個物件各自一個檔案，依 `catalog`/`ops` 結構描述資料夾整理），可建置出以統一 **AdventureGearAI** 資料庫為目標的 DACPAC。`DP800.publish.xml` 是範圍限定於 `AdventureGearAI` 的無密碼 Entra 發佈設定檔；其中不含密碼祕密。執行 `local/Build-SqlProject.ps1` 可建置專案（0 個警告／0 個錯誤）。`azure/build-deploy.yml` 是 GitHub Actions 工作流程範例，會建置 DACPAC，並僅使用祕密連接字串來發佈。

## 執行目標

所有物件都位於 `AdventureGearAI`（`catalog.InventoryChangeLog`、`catalog.usp_LogInventoryChange`、`ops.DeploymentLog`）。統一示範執行器會以混合式命令佈建這些物件：

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 7
```

執行器會對 `AdventureGearAI` 執行具等冪性的 `common/01-inventory-deployment-log.sql` 設定指令碼；SQL 專案建置會另行示範（它產生 CI/CD 工作流程使用的 DACPAC），因此資訊清單列出的是 SQL 設定指令碼，而不是專案建置。
