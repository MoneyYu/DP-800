SELECT
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    d.name,
    d.is_encrypted
FROM sys.databases AS d
WHERE d.name = DB_NAME();

EXECUTE AS USER = N'DP800_MaskedReader';
SELECT CustomerName, Email, GovernmentID, CreditLimit, SalesRegion
FROM dbo.SecureCustomers;
REVERT;

EXECUTE AS USER = N'DP800_WestReader';
SELECT CustomerName, Email, GovernmentID, CreditLimit, SalesRegion
FROM dbo.SecureCustomers;
REVERT;

SELECT
    N'Always Encrypted requires a client driver configured with a column master key and column encryption key.' AS AlwaysEncryptedLocalResult,
    N'EncryptedCardNumber remains NULL in this server-only demo.' AS Reason;
GO
