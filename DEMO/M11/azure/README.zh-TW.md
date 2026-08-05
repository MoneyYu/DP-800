繁體中文 | [English](README.md)

# Azure RAG 路徑

1. 請在 Azure SQL Database 中執行，而非在本機 SQL Server 容器中。
2. 在此存放庫外部，使用受控識別建立端點資料庫範圍認證。
3. 授與資料庫識別對已核准 Azure OpenAI 部署的存取權。
4. 只授與呼叫者必要的程序權限；`EXECUTE ANY EXTERNAL ENDPOINT` 的權限很強大。
5. 請在執行階段提供端點／部署 SQLCMD 變數，絕不可認可金鑰、權杖、租用戶 ID 或物件 ID。
6. 擷取已從 `search` 結構描述讀取（由正規 AdventureGearAI 產品與評論建立的 `search.SearchDocuments`）。若要取得更豐富的語意擷取，請將其延伸為 M09/M10 內嵌與向量搜尋路徑。
