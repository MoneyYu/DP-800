繁體中文 | [English](README.md)

# Azure 注意事項

- Azure SQL Database 預設會啟用 TDE，並管理 AdventureGearAI 資料庫的服務端
  保護；客戶自控金鑰需要 Azure Key Vault 設定。
- 請盡可能使用針對 Azure 資源設定的 Entra 使用者/群組及稽核目的地，而非包含式
  SQL 使用者。
- Always Encrypted 需要具有 `Column Encryption Setting=Enabled` 的用戶端及
  已核准的金鑰存放區。請勿將金鑰材料放入此存放庫。
- DDM 不是加密界限，具權限的使用者仍能看到未遮罩值。
