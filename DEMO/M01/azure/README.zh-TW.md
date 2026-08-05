繁體中文 | [English](README.md)

# Azure 注意事項

請針對裝載 AdventureGearAI 結構描述集合的 Azure SQL 資料庫執行本模組設定。
Azure SQL 提供時態資料表、已建立索引的計算 JSON 資料行、範圍資料分割，以及
SQL 圖形節點/邊緣資料表，但 Azure SQL 管理儲存體，並不提供與盒裝 SQL Server
相同的檔案群組設計選項，因此 `PS_AdventureGear_OrderDate` 會對應至主要檔案群組。
教學前，請在目標資料庫中確認服務目標、分類帳需求及任何預覽狀態。
