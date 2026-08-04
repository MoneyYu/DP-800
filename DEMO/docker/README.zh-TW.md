# SQL Server 2025 Full-Text 與 PolyBase 示範映像

此映像是 DP-800 本機示範所需功能的官方映像式作法。容器建立後，沒有
SQL Server 環境變數可安裝或啟用 Full-Text Search (FTS) 或 PolyBase；請改用
此自訂映像。

建置映像：

```powershell
pwsh -NoProfile -File DEMO/docker/Build-DemoImage.ps1
```

若要建置並執行暫時且隔離的探針，請在目前程序設定
`DP800_SQL_PASSWORD`，或於安全提示輸入密碼。`-ProbePort` 可指定主機連接
埠；未指定時，指令碼會選擇可用的 loopback 連接埠。

```powershell
pwsh -NoProfile -File DEMO/docker/Build-DemoImage.ps1 -RunProbe -ProbePort 11433
```

探針名稱為 `dp800-sql2025-feature-probe`，使用非 1433 的連接埠，且與
`mssql2025` 完全分離。請以 `docker exec` 與 `sqlcmd` 驗證後，只移除該探針：

```powershell
docker rm -f dp800-sql2025-feature-probe
```

一般本機示範路徑仍是外部管理的 `mssql2025` 容器
`127.0.0.1:1433`；在其中使用既有的 `DEMO/bootstrap` 與模組指令碼。請勿對
目前容器新增 volume 或就地安裝套件。若要以此映像取代它，必須先規劃資料庫
備份與資料移轉，因為新容器不會帶有既有容器的資料。
