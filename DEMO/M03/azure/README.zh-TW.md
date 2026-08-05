繁體中文 | [English](README.md)

# Azure 注意事項

請針對目標 Azure SQL 伺服器上的 AdventureGearAI 資料庫執行 common 與查詢指令碼，
並記錄引擎版本/版本資訊。`REGEXP_LIKE` 等規則運算式函式會因版本而異，因此應保留
功能偵測結果，而非假設與本機 SQL Server 2025 組建的平台一致性。Azure SQL 支援
遞迴 CTE、視窗函式、`OPENJSON` 及 SQL 圖形 `MATCH`。
