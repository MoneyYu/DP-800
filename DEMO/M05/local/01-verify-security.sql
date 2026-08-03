/*
    M05 local/01-verify-security.sql

    Read-only verification of the Module 5 security surfaces against
    AdventureGearAI: TDE inspection, Dynamic Data Masking under a masked reader,
    Row-Level Security under a region-scoped reader, and an Always Encrypted note.
    Safe to re-run.
*/
SET NOCOUNT ON;
GO

/* TDE / encryption inspection for the current database. */
SELECT
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    d.name,
    d.is_encrypted
FROM sys.databases AS d
WHERE d.name = DB_NAME();

/* Dynamic Data Masking: the masked reader sees masked email/GovernmentID/CreditLimit. */
EXECUTE AS USER = N'AdventureGearMaskedReader';
SELECT CustomerName, Email, GovernmentID, CreditLimit, SalesRegion
FROM security.SecureCustomers
ORDER BY CustomerID;
REVERT;

/* Row-Level Security: the West reader only sees West-region customers. */
EXECUTE AS USER = N'AdventureGearWestReader';
SELECT CustomerName, Email, GovernmentID, CreditLimit, SalesRegion
FROM security.SecureCustomers
ORDER BY CustomerID;
REVERT;

/* Always Encrypted is a client-driver capability, not server-side T-SQL. */
SELECT
    N'Always Encrypted requires a client driver configured with a column master key and column encryption key.' AS AlwaysEncryptedLocalResult,
    N'EncryptedCardNumber remains NULL in this server-only demo.' AS Reason;
GO
