繁體中文 | [English](README.md)

# 本機 DAB

1. 安裝已釘選版本的 DAB CLI：`dotnet tool install --global Microsoft.DataApiBuilder --version 2.0.9`。
2. 在目前處理序中設定 `DATABASE_CONNECTION_STRING`。請從 SQL 包裝函式使用的同一個安全密碼來源建立它；請勿將它儲存於存放庫或殼層歷程記錄中。
3. 執行 `dab start --config DEMO/M08/common/dab-config.json`。
4. 測試 `http://localhost:5000/api/Product` 和 `http://localhost:5000/graphql`。

本機 SQL 驗證僅是講師便利措施。存放庫不會提供或保存連接字串。

執行階段測試 `DEMO/tests/Test-DabIntegrationRuntime.ps1` 會安裝或使用確切的 DAB 2.0.9、對 `mssql2025` 執行正常 M08 設定，並確認此設定可實際執行 REST 與 GraphQL relationship 端點。
