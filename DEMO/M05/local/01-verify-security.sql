/*
    M05 local/01-verify-security.sql

    Read-only verification of the Module 5 security surfaces against
    AdventureGearAI: TDE inspection, Dynamic Data Masking under a masked reader,
    Row-Level Security under a region-scoped reader, and an Always Encrypted note.
    Safe to re-run.
    * 以唯讀方式驗證 AdventureGearAI 的模組 5 安全性介面：TDE、動態資料遮罩、資料列層級安全性與 Always Encrypted 說明；可安全重複執行。
*/
SET NOCOUNT ON;
GO

/* TDE / encryption inspection for the current database.
    * 檢查目前資料庫的 TDE 與加密狀態。
*/
SELECT
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    d.name,
    d.is_encrypted
FROM sys.databases AS d
WHERE d.name = DB_NAME();

/* Dynamic Data Masking: the masked reader sees masked email/GovernmentID/
   CreditLimit/PrivateNote. PrivateNote demonstrates the fourth default() mask.
    * 遮罩讀取者會看到已遮罩的電子郵件、GovernmentID、CreditLimit 與 PrivateNote；PrivateNote 示範第四種 default() 遮罩。
*/
EXECUTE AS USER = N'AdventureGearMaskedReader';
SELECT CustomerName, Email, GovernmentID, CreditLimit, PrivateNote AS DefaultMaskedValue, SalesRegion
FROM security.SecureCustomers
ORDER BY CustomerID;
REVERT;

/* Row-Level Security: the West reader only sees West-region customers.
    * West 讀取者只能看到 West 區域客戶。
*/
EXECUTE AS USER = N'AdventureGearWestReader';
SELECT CustomerName, Email, GovernmentID, CreditLimit, PrivateNote AS DefaultMaskedValue, SalesRegion
FROM security.SecureCustomers
ORDER BY CustomerID;
REVERT;

/* Object-level GRANT EXECUTE succeeds, while the explicit DENY SELECT remains
   effective for the same contained user.
   * 物件層級的 GRANT EXECUTE 會成功，而相同內含使用者的 DENY SELECT 仍會生效。
*/
EXECUTE AS USER = N'AdventureGearPermissionReader';
EXEC security.usp_GetSecureCustomer @CustomerID = 1;
BEGIN TRY
    SELECT TOP (1) CustomerID
    FROM security.SecureCustomers;
    SELECT N'DENY was not applied.' AS ObjectPermissionResult;
END TRY
BEGIN CATCH
    SELECT N'Direct SELECT denied as expected.' AS ObjectPermissionResult;
END CATCH;
REVERT;

/* Always Encrypted is a client-driver capability, not server-side T-SQL.
    * Always Encrypted 是用戶端驅動程式能力，而非伺服器端 T-SQL 功能。
*/
SELECT
    N'Always Encrypted requires a client driver configured with a column master key and column encryption key.' AS AlwaysEncryptedLocalResult,
    N'EncryptedCardNumber remains NULL in this server-only demo.' AS Reason;
GO
