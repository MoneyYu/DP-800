SET NOCOUNT ON;
GO

DROP SECURITY POLICY IF EXISTS Security.CustomerRegionPolicy;
DROP FUNCTION IF EXISTS Security.fn_RegionFilter;
DROP USER IF EXISTS DP800_MaskedReader;
DROP USER IF EXISTS DP800_WestReader;
DROP TABLE IF EXISTS dbo.SecureCustomers;
IF SCHEMA_ID(N'Security') IS NULL EXEC(N'CREATE SCHEMA Security AUTHORIZATION dbo;');
GO

CREATE TABLE dbo.SecureCustomers
(
    CustomerID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_SecureCustomers PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    Email nvarchar(200) MASKED WITH (FUNCTION = 'email()') NOT NULL,
    GovernmentID char(11) MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)') NOT NULL,
    CreditLimit decimal(12,2) MASKED WITH (FUNCTION = 'random(1000,9000)') NOT NULL,
    SalesRegion nvarchar(20) NOT NULL,
    EncryptedCardNumber varbinary(256) NULL
);

INSERT dbo.SecureCustomers (CustomerName, Email, GovernmentID, CreditLimit, SalesRegion) VALUES
    (N'Avery Chen', N'avery.chen@example.invalid', '111-22-3333', 8000, N'West'),
    (N'Morgan Lee', N'morgan.lee@example.invalid', '222-33-4444', 6500, N'East'),
    (N'Jordan Patel', N'jordan.patel@example.invalid', '333-44-5555', 5000, N'Central');

CREATE USER DP800_MaskedReader WITHOUT LOGIN;
CREATE USER DP800_WestReader WITHOUT LOGIN;
GRANT SELECT ON dbo.SecureCustomers TO DP800_MaskedReader, DP800_WestReader;
GO

CREATE OR ALTER FUNCTION Security.fn_RegionFilter(@SalesRegion nvarchar(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS Allowed
    WHERE USER_NAME() NOT IN (N'DP800_WestReader')
       OR @SalesRegion = N'West'
);
GO

CREATE SECURITY POLICY Security.CustomerRegionPolicy
ADD FILTER PREDICATE Security.fn_RegionFilter(SalesRegion)
ON dbo.SecureCustomers
WITH (STATE = ON);
GO
