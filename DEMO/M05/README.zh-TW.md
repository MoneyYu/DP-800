繁體中文 | [English](README.md)

# M05 — 資料安全性與合規性

模組 5 會針對標準 **AdventureGearAI** 客戶資料示範資料保護功能。它不會取代
`customer.Customers`；而是會佈建受保護的伴隨投影
（`security.SecureCustomers`），該投影包含 Dynamic Data Masking 所需的僅供示範
敏感資料行，以及 `security` 結構描述中的 Row-Level Security 原則。

## 執行方式

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 5
```

執行器會針對 AdventureGearAI 執行 `common/01-security.sql`，然後執行
`local/01-verify-security.sql`。示範使用者專屬於本模組，且每次執行都會重設
（卸除/重新建立），所以使用 `-Force` 重新執行是安全的。

## 示範內容

- 受保護投影上的 Dynamic Data Masking（`email()`、`partial`、`random`）。
- 透過 `security.fn_RegionFilter` + `security.CustomerRegionPolicy` 實作的
  Row-Level Security。
- TDE 檢查（`sys.databases.is_encrypted`）。
- Always Encrypted 用戶端驅動程式界限（說明其行為，但不偽造伺服器端實作）。

TDE 憑證/金鑰生命週期因平台而異，不會以硬式編碼的主要金鑰密碼自動處理。
DDM 不是加密界限；具權限的使用者仍能看到未遮罩值。請參閱 `azure/README.md`。
