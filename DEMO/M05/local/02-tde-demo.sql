/*
    M05 local/02-tde-demo.sql

    Manual Transparent Data Encryption demonstration. It creates and removes
    exactly the temporary DP800_M05_TdeDemo database; AdventureGearAI is never
    encrypted or altered. The server certificate is removed during cleanup.

    If master does not already have a database master key, provide a strong,
    uncommitted TdeDemoMasterKeyPassword SQLCMD variable.
    * 手動 Transparent Data Encryption 示範：只會建立及移除暫存的
      DP800_M05_TdeDemo 資料庫；絕不加密或變更 AdventureGearAI。伺服器憑證會在清除時移除。
*/
USE master;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DemoDatabase sysname = N'DP800_M05_TdeDemo';
DECLARE @Certificate sysname = N'DP800_M05_TdeDemoCertificate';
DECLARE @Sql nvarchar(max);

BEGIN TRY
    IF DB_ID(@DemoDatabase) IS NOT NULL
        THROW 51050, N'DP800_M05_TdeDemo already exists. Remove only that prior temporary demo database before rerunning.', 1;

    IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = @Certificate)
        THROW 51051, N'DP800_M05_TdeDemoCertificate already exists. Remove only that prior temporary demo certificate before rerunning.', 1;

    /* A server certificate requires a master database master key. Existing
       server configuration is reused; a newly created key is retained as
       server cryptographic infrastructure rather than dropped by this demo. */
    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    BEGIN
        IF N'$(TdeDemoMasterKeyPassword)' = N''
            THROW 51052, N'TdeDemoMasterKeyPassword is required when master has no database master key.', 1;

        CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(TdeDemoMasterKeyPassword)';
    END;

    CREATE CERTIFICATE DP800_M05_TdeDemoCertificate
    WITH SUBJECT = N'DP-800 M05 temporary TDE demonstration certificate';

    SET @Sql = N'CREATE DATABASE ' + QUOTENAME(@DemoDatabase) + N';';
    EXEC (@Sql);
    SET @Sql = N'USE ' + QUOTENAME(@DemoDatabase) + N';
                 CREATE DATABASE ENCRYPTION KEY
                 WITH ALGORITHM = AES_256
                 ENCRYPTION BY SERVER CERTIFICATE ' + QUOTENAME(@Certificate) + N';
                 ALTER DATABASE CURRENT SET ENCRYPTION ON;';
    EXEC (@Sql);

    /* State 2 is encryption in progress; state 3 is fully encrypted. */
    SELECT
        d.name AS DatabaseName,
        d.is_encrypted,
        dek.encryption_state,
        dek.encryption_state_desc
    FROM sys.databases AS d
    INNER JOIN sys.dm_database_encryption_keys AS dek ON dek.database_id = d.database_id
    WHERE d.name = @DemoDatabase;

    ALTER DATABASE [DP800_M05_TdeDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [DP800_M05_TdeDemo];
    DROP CERTIFICATE DP800_M05_TdeDemoCertificate;

    PRINT N'M05 TDE demo verified and cleaned up DP800_M05_TdeDemo.';
END TRY
BEGIN CATCH
    /* TRY/finally-style cleanup: only the exact temporary database and the
       certificate created for it are candidates for removal. */
    IF DB_ID(N'DP800_M05_TdeDemo') IS NOT NULL
    BEGIN
        ALTER DATABASE [DP800_M05_TdeDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE [DP800_M05_TdeDemo];
    END;

    IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'DP800_M05_TdeDemoCertificate')
        DROP CERTIFICATE DP800_M05_TdeDemoCertificate;

    THROW;
END CATCH;
GO
