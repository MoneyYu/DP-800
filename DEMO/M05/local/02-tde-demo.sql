/*
    M05 local/02-tde-demo.sql

    Manual Transparent Data Encryption demonstration. It creates and removes
    exactly the temporary DP800_M05_TdeDemo database; AdventureGearAI is never
    encrypted or altered. The server certificate is removed during cleanup.

    A pre-existing master database master key is required. This demo never
    creates or drops server-wide cryptographic infrastructure.
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
DECLARE @OwnsDatabase bit = 0;
DECLARE @OwnsCertificate bit = 0;
DECLARE @DatabaseId int;
DECLARE @CertificateThumbprint varbinary(32);
DECLARE @AppLockResult int;
DECLARE @AppLockHeld bit = 0;

BEGIN TRY
    EXEC @AppLockResult = sys.sp_getapplock
        @Resource = N'DP800_M05_TdeDemo',
        @LockMode = N'Exclusive',
        @LockOwner = N'Session',
        @LockTimeout = 0;

    IF @AppLockResult < 0
        THROW 51049, N'Another DP800 M05 TDE demo session is active. Try again after it completes.', 1;
    SET @AppLockHeld = 1;

    IF DB_ID(@DemoDatabase) IS NOT NULL
        THROW 51050, N'DP800_M05_TdeDemo already exists. Remove only that prior temporary demo database before rerunning.', 1;

    IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = @Certificate)
        THROW 51051, N'DP800_M05_TdeDemoCertificate already exists. Remove only that prior temporary demo certificate before rerunning.', 1;

    /* A server certificate requires a master database master key. Do not
       create one: it is server-wide infrastructure outside this demo's scope. */
    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
        THROW 51052, N'master requires an existing database master key before this TDE demo can run.', 1;

    CREATE CERTIFICATE DP800_M05_TdeDemoCertificate
    WITH SUBJECT = N'DP-800 M05 temporary TDE demonstration certificate';
    SELECT @CertificateThumbprint = thumbprint
    FROM sys.certificates
    WHERE name = @Certificate;
    SET @OwnsCertificate = CASE WHEN @CertificateThumbprint IS NULL THEN 0 ELSE 1 END;
    IF @OwnsCertificate = 0
        THROW 51055, N'Could not record ownership of DP800_M05_TdeDemoCertificate.', 1;

    SET @Sql = N'CREATE DATABASE ' + QUOTENAME(@DemoDatabase) + N';';
    EXEC (@Sql);
    SET @DatabaseId = DB_ID(@DemoDatabase);
    SET @OwnsDatabase = CASE WHEN @DatabaseId IS NULL THEN 0 ELSE 1 END;
    IF @OwnsDatabase = 0
        THROW 51056, N'Could not record ownership of DP800_M05_TdeDemo.', 1;
    SET @Sql = N'USE ' + QUOTENAME(@DemoDatabase) + N';
                 EXEC sys.sp_addextendedproperty
                     @name = N''DP800_M05_TdeDemoOwnershipToken'',
                     @value = N''created-by-this-tde-demo'';';
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

    IF @OwnsDatabase = 1 AND DB_ID(@DemoDatabase) = @DatabaseId
    BEGIN
        SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@DemoDatabase) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                     DROP DATABASE ' + QUOTENAME(@DemoDatabase) + N';';
        EXEC (@Sql);
        SET @OwnsDatabase = 0;
    END;

    IF @OwnsDatabase = 1
        THROW 51053, N'Could not verify ownership of DP800_M05_TdeDemo; it was not removed.', 1;

    IF @OwnsCertificate = 1
       AND EXISTS
       (
           SELECT 1
           FROM sys.certificates
           WHERE name = @Certificate
             AND thumbprint = @CertificateThumbprint
       )
    BEGIN
        SET @Sql = N'DROP CERTIFICATE ' + QUOTENAME(@Certificate) + N';';
        EXEC (@Sql);
        SET @OwnsCertificate = 0;
    END;

    IF @OwnsCertificate = 1
        THROW 51054, N'Could not verify ownership of DP800_M05_TdeDemoCertificate; it was not removed.', 1;

    IF @AppLockHeld = 1
        EXEC sys.sp_releaseapplock @Resource = N'DP800_M05_TdeDemo', @LockOwner = N'Session';

    PRINT N'M05 TDE demo verified and cleaned up DP800_M05_TdeDemo.';
END TRY
BEGIN CATCH
    /* Ownership is recorded immediately after CREATE statements. The current
       identity check prevents removal of a pre-existing collision or a
       replacement resource, including before the marker can be created. */
    IF @OwnsDatabase = 1 AND DB_ID(@DemoDatabase) = @DatabaseId
    BEGIN
        SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@DemoDatabase) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                     DROP DATABASE ' + QUOTENAME(@DemoDatabase) + N';';
        EXEC (@Sql);
        SET @OwnsDatabase = 0;
    END;

    IF @OwnsCertificate = 1
       AND EXISTS
       (
           SELECT 1
           FROM sys.certificates
           WHERE name = @Certificate
             AND thumbprint = @CertificateThumbprint
       )
    BEGIN
        SET @Sql = N'DROP CERTIFICATE ' + QUOTENAME(@Certificate) + N';';
        EXEC (@Sql);
        SET @OwnsCertificate = 0;
    END;

    IF @AppLockHeld = 1
        EXEC sys.sp_releaseapplock @Resource = N'DP800_M05_TdeDemo', @LockOwner = N'Session';

    THROW;
END CATCH;
GO
