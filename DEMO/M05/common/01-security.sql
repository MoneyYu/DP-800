/*
    M05 common/01-security.sql

    Module 5 (Data security and compliance) for AdventureGearAI. The security demo
    is built on the canonical customer data. It does NOT replace the core
    customer.Customers table; instead it provisions a secured companion
    projection (security.SecureCustomers) that carries the extra demo-only
    sensitive columns that Dynamic Data Masking requires in the column
    definition, plus a Row-Level Security policy in the security schema.

    Idempotent: policy, function, users, and the companion table are dropped
    (guarded) and recreated, and the projection is re-seeded from the canonical
    customers on every run. The demo users are unique to this module and are
    reset (dropped/recreated) each run.
    * 模組 5 的 AdventureGearAI 安全性與合規性示範建立 security.SecureCustomers 伴隨投影、動態資料遮罩與資料列層級安全性；不會取代標準 customer.Customers，且每次執行均會重建本模組物件。
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DROP SECURITY POLICY IF EXISTS security.CustomerRegionPolicy;
DROP FUNCTION IF EXISTS security.fn_RegionFilter;
DROP USER IF EXISTS AdventureGearMaskedReader;
DROP USER IF EXISTS AdventureGearWestReader;
DROP TABLE IF EXISTS security.SecureCustomers;
GO

/* Secured companion projection of the canonical customers. The demo-only
   GovernmentID / CreditLimit columns exist so masking functions have a column to
   * 建立標準客戶的安全伴隨投影，示範專用敏感欄位由 CustomerID 決定性產生。
   bind to; they are synthesized deterministically from the canonical CustomerID. */
CREATE TABLE security.SecureCustomers
(
    CustomerID int NOT NULL CONSTRAINT PK_SecureCustomers PRIMARY KEY,
    CustomerName nvarchar(120) NOT NULL,
    Email nvarchar(200) MASKED WITH (FUNCTION = 'email()') NOT NULL,
    GovernmentID char(11) MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)') NOT NULL,
    CreditLimit decimal(12,2) MASKED WITH (FUNCTION = 'random(1000,9000)') NOT NULL,
    SalesRegion nvarchar(20) NOT NULL,
    EncryptedCardNumber varbinary(256) NULL,
    CONSTRAINT FK_SecureCustomers_Customers FOREIGN KEY (CustomerID) REFERENCES customer.Customers(CustomerID)
);

INSERT security.SecureCustomers (CustomerID, CustomerName, Email, GovernmentID, CreditLimit, SalesRegion)
SELECT
    c.CustomerID,
    c.CustomerName,
    c.Email,
    CONCAT(
        RIGHT(CONCAT('00', 100 + c.CustomerID), 3), '-',
        RIGHT(CONCAT('0', c.CustomerID), 2), '-',
        RIGHT(CONCAT('000', 1000 + c.CustomerID), 4)),
    5000 + (c.CustomerID * 500),
    c.SalesRegion
FROM customer.Customers AS c;
GO

/* Contained users unique to this module (no server login), reset each run.
    * 建立本模組專屬、沒有伺服器登入的內含使用者，並於每次執行時重設。
*/
CREATE USER AdventureGearMaskedReader WITHOUT LOGIN;
CREATE USER AdventureGearWestReader WITHOUT LOGIN;
GRANT SELECT ON security.SecureCustomers TO AdventureGearMaskedReader, AdventureGearWestReader;
GO

/* Row-Level Security predicate: the West reader only sees West-region rows.
    * 資料列層級安全性述詞讓 West 讀取者只看到 West 區域資料列。
*/
CREATE OR ALTER FUNCTION security.fn_RegionFilter(@SalesRegion nvarchar(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS Allowed
    WHERE USER_NAME() NOT IN (N'AdventureGearWestReader')
       OR @SalesRegion = N'West'
);
GO

CREATE SECURITY POLICY security.CustomerRegionPolicy
ADD FILTER PREDICATE security.fn_RegionFilter(SalesRegion)
ON security.SecureCustomers
WITH (STATE = ON);
GO

PRINT N'M05 security objects created against AdventureGearAI (security schema).';
GO
