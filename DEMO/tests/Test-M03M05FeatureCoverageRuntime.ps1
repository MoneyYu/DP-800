[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa'
)

# Focused, runtime-only contract for the M03 JSON and M05 security demos. The
# caller supplies DP800_SQL_PASSWORD or SQLCMDPASSWORD in this process; it is
# never read from Docker, emitted, or put on a command line.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$database = 'AdventureGearAI'
$tdeDatabase = 'DP800_M05_TdeDemo'
$tdeCertificate = 'DP800_M05_TdeDemoCertificate'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Invoke-Query {
    param(
        [string]$Database,
        [string]$Query,
        [hashtable]$SqlCmdVariables
    )

    $originalVariables = @{}
    try {
        if ($SqlCmdVariables) {
            foreach ($name in $SqlCmdVariables.Keys) {
                $originalVariables[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                [Environment]::SetEnvironmentVariable($name, [string]$SqlCmdVariables[$name], 'Process')
            }
        }

        $arguments = @('-S', $Server, '-U', $User, '-d', $Database, '-Q', $Query, '-h', '-1', '-W', '-b', '-C', '-I')
        if (-not $SqlCmdVariables) { $arguments += '-x' }
        $result = & $sqlcmd.Source @arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed against '$Database': $($result -join ' ')" }
        return @($result | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
    }
    finally {
        foreach ($name in $originalVariables.Keys) {
            [Environment]::SetEnvironmentVariable($name, $originalVariables[$name], 'Process')
        }
    }
}
function Invoke-SqlScript {
    param([string]$Database, [string]$Path)

    $result = & $sqlcmd.Source -S $Server -U $User -d $Database -i $Path -h -1 -W -b -C -r 1 -f 65001 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd script failed for '$Path': $($result -join ' ')" }
    return ($result | Out-String)
}
function Invoke-SqlScriptExpectFailure {
    param([string]$Database, [string]$Path)

    $result = & $sqlcmd.Source -S $Server -U $User -d $Database -i $Path -h -1 -W -b -C -r 1 -f 65001 2>&1
    if ($LASTEXITCODE -eq 0) { throw "sqlcmd script unexpectedly succeeded for '$Path': $($result -join ' ')" }
    return ($result | Out-String)
}
function Get-Scalar {
    param(
        [string]$Database,
        [string]$Query,
        [hashtable]$SqlCmdVariables
    )
    return (Invoke-Query -Database $Database -Query $Query -SqlCmdVariables $SqlCmdVariables | Select-Object -First 1)
}
function New-TestMasterKeyPassword {
    $bytes = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return "D800!t$([Convert]::ToHexString($bytes))"
}

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) { Write-Host 'SKIP: sqlcmd is not available.' -ForegroundColor Yellow; exit 0 }
if ([string]::IsNullOrWhiteSpace($env:DP800_SQL_PASSWORD) -and [string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    Write-Host 'SKIP: set DP800_SQL_PASSWORD or SQLCMDPASSWORD in this process.' -ForegroundColor Yellow
    exit 0
}
$originalSqlcmdPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$testPassword = if ($env:DP800_SQL_PASSWORD) { $env:DP800_SQL_PASSWORD } else { $env:SQLCMDPASSWORD }
[Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $testPassword, 'Process')

$bootstrap = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$m03Common = Join-Path $demoRoot 'M03\common\01-advanced-objects.sql'
$m03Local = Join-Path $demoRoot 'M03\local\01-advanced-queries.sql'
$m05Common = Join-Path $demoRoot 'M05\common\01-security.sql'
$m05Local = Join-Path $demoRoot 'M05\local\01-verify-security.sql'
$m05Tde = Join-Path $demoRoot 'M05\local\02-tde-demo.sql'
$m05Reset = Join-Path $demoRoot 'M05\reset\reset.sql'
$createdTdeCollisionDatabase = $false
$createdTdeCollisionCertificate = $false
$createdTdeMarkerCollision = $false
$preMarkerDatabaseIdentity = $null
$preMarkerCertificateThumbprint = $null
$masterKeyExistedBeforeTde = $false
$masterKeyIdentityBeforeTde = $null
$createdTestMasterKey = $false
$testMasterKeyPassword = $null
$testMasterKeyIdentity = $null
$adventureGearEncryptionBeforeTde = $null

try {
    # Bootstrap and execute the production scripts, rather than reproducing
    # their SQL in the test.
    & pwsh -NoProfile -File $bootstrap -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Core bootstrap failed during M03/M05 test setup.' }
    Invoke-SqlScript -Database $database -Path $m03Common | Out-Null
    $m03Output = Invoke-SqlScript -Database $database -Path $m03Local
    if ($m03Output -notmatch '(?s)"OrderID"\s*:') {
        Add-Failure 'M03 FOR JSON PATH customer/order detail output was not returned.'
    }
    if ($m03Output -notmatch '(?s)(rocky trails|mixed-surface|aluminum|alloy)') {
        Add-Failure 'M03 OPENJSON native-column output was not returned.'
    }
    if ((Get-Scalar -Database $database -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM catalog.Products
    WHERE ProductMetadata IS NOT NULL
      AND JSON_CONTAINS(ProductMetadata, N'trail', N'$.compatibility.terrainTags[*]') = 1
) THEN N'PASS' ELSE N'FAIL' END;
"@) -ne 'PASS') {
        Add-Failure 'M03 JSON_CONTAINS did not match the native ProductMetadata column.'
    }

    Invoke-SqlScript -Database $database -Path $m05Common | Out-Null
    $m05Output = Invoke-SqlScript -Database $database -Path $m05Local
    if ($m05Output -notmatch '(?s)XXXX') {
        Add-Failure 'M05 verification did not return the fourth default() masked column.'
    }
    if ((Get-Scalar -Database $database -Query @"
SET NOCOUNT ON;
EXECUTE AS USER = N'AdventureGearMaskedReader';
DECLARE @result nvarchar(20) =
(
    SELECT TOP (1) PrivateNote
    FROM security.SecureCustomers
    ORDER BY CustomerID
);
REVERT;
SELECT CASE WHEN @result = N'XXXX' THEN N'PASS' ELSE CONCAT(N'FAIL:', @result) END;
"@) -ne 'PASS') {
        Add-Failure 'M05 default() masking did not hide PrivateNote as XXXX.'
    }
    $executeResult = Get-Scalar -Database $database -Query @"
SET NOCOUNT ON;
EXECUTE AS USER = N'AdventureGearPermissionReader';
BEGIN TRY
    EXEC security.usp_GetSecureCustomer @CustomerID = 1;
    SELECT N'EXECUTE_GRANTED';
END TRY
BEGIN CATCH
    SELECT CONCAT(N'EXECUTE_FAILED:', ERROR_NUMBER());
END CATCH;
REVERT;
"@
    if ($executeResult -notmatch '^1\s+') {
        Add-Failure 'M05 object-level GRANT EXECUTE was not effective under EXECUTE AS.'
    }
    if ((Get-Scalar -Database $database -Query @"
SET NOCOUNT ON;
EXECUTE AS USER = N'AdventureGearPermissionReader';
BEGIN TRY
    SELECT TOP (1) CustomerID FROM security.SecureCustomers;
    SELECT N'DENY_FAILED';
END TRY
BEGIN CATCH
    SELECT N'SELECT_DENIED';
END CATCH;
REVERT;
"@) -ne 'SELECT_DENIED') {
        Add-Failure 'M05 object-level DENY SELECT was not effective under EXECUTE AS.'
    }

    if (-not (Test-Path -LiteralPath $m05Tde -PathType Leaf)) {
        Add-Failure 'M05 manual TDE demo script is missing.'
    }
    else {
        $masterKeyExistedBeforeTde = (Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM sys.symmetric_keys
    WHERE name = N'##MS_DatabaseMasterKey##'
) THEN N'YES' ELSE N'NO' END;
"@) -eq 'YES'
        $masterKeyIdentityBeforeTde = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONVERT(nvarchar(36), key_guid)
FROM sys.symmetric_keys
WHERE name = N'##MS_DatabaseMasterKey##';
"@
        $adventureGearEncryptionBeforeTde = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(d.is_encrypted, N':', ISNULL(CONVERT(nvarchar(10), dek.encryption_state), N'NULL'))
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON dek.database_id = d.database_id
WHERE d.name = N'$database';
"@

        if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN DB_ID(N'$tdeDatabase') IS NOT NULL THEN N'YES' ELSE N'NO' END;
"@) -eq 'YES' -or (Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$tdeCertificate')
            THEN N'YES' ELSE N'NO' END;
"@) -eq 'YES') {
            Add-Failure 'M05 TDE collision test requires no pre-existing DP800 TDE database or certificate.'
        }
        elseif ((Get-Scalar -Database 'model' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM sys.extended_properties
    WHERE class = 0
      AND name = N'DP800_M05_TdeDemoOwnershipToken'
) THEN N'YES' ELSE N'NO' END;
"@) -eq 'YES') {
            Add-Failure 'M05 TDE pre-marker collision test requires no pre-existing model ownership marker.'
        }
        else {
            if (-not $masterKeyExistedBeforeTde) {
                # The production demo must reject an absent key rather than
                # creating server-wide cryptographic infrastructure.
                $absentKeyOutput = Invoke-SqlScriptExpectFailure -Database 'master' -Path $m05Tde
                if ($absentKeyOutput -notmatch '51052|requires an existing database master key') {
                    Add-Failure 'M05 TDE absent-key preflight did not report the required master database master key.'
                }
                if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM sys.symmetric_keys
    WHERE name = N'##MS_DatabaseMasterKey##'
) THEN N'FAIL' ELSE N'PASS' END;
"@) -ne 'PASS') {
                    Add-Failure 'M05 TDE absent-key preflight created a master database master key.'
                }

                $testMasterKeyPassword = New-TestMasterKeyPassword
                Invoke-Query -Database 'master' -Query @'
CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(TdeTestMasterKeyPassword)';
'@ -SqlCmdVariables @{ TdeTestMasterKeyPassword = $testMasterKeyPassword } | Out-Null
                $createdTestMasterKey = $true
                $testMasterKeyIdentity = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONVERT(nvarchar(36), key_guid)
FROM sys.symmetric_keys
WHERE name = N'##MS_DatabaseMasterKey##';
"@
                if ([string]::IsNullOrWhiteSpace($testMasterKeyIdentity)) {
                    Add-Failure 'M05 TDE test could not identify its temporary master database master key.'
                }
            }

            Invoke-Query -Database 'master' -Query @"
CREATE CERTIFICATE [$tdeCertificate]
WITH SUBJECT = N'DP-800 M05 runtime collision fixture';
"@ | Out-Null
            $createdTdeCollisionCertificate = $true
            Invoke-Query -Database 'master' -Query "CREATE DATABASE [$tdeDatabase];" | Out-Null
            $createdTdeCollisionDatabase = $true
            $collisionDatabaseIdentity = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(database_id, N':', CONVERT(nvarchar(33), create_date, 126), N':', is_encrypted)
FROM sys.databases
WHERE name = N'$tdeDatabase';
"@
            $collisionCertificateThumbprint = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONVERT(varchar(130), thumbprint, 1)
FROM sys.certificates
WHERE name = N'$tdeCertificate';
"@

            $collisionOutput = Invoke-SqlScriptExpectFailure -Database 'master' -Path $m05Tde
            if ($collisionOutput -notmatch '51050|already exists') {
                Add-Failure 'M05 TDE collision preflight did not report the existing database.'
            }
            if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN CONCAT(database_id, N':', CONVERT(nvarchar(33), create_date, 126), N':', is_encrypted) = N'$collisionDatabaseIdentity'
            THEN N'PASS' ELSE N'FAIL' END
FROM sys.databases
WHERE name = N'$tdeDatabase';
"@) -ne 'PASS') {
                Add-Failure 'M05 TDE collision preflight altered or removed the existing database.'
            }
            if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN CONVERT(varchar(130), thumbprint, 1) = N'$collisionCertificateThumbprint'
            THEN N'PASS' ELSE N'FAIL' END
FROM sys.certificates
WHERE name = N'$tdeCertificate';
"@) -ne 'PASS') {
                Add-Failure 'M05 TDE collision preflight altered or removed the existing certificate.'
            }

            Invoke-Query -Database 'master' -Query @"
ALTER DATABASE [$tdeDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$tdeDatabase];
"@ | Out-Null
            $createdTdeCollisionDatabase = $false
            Invoke-Query -Database 'master' -Query "DROP CERTIFICATE [$tdeCertificate];" | Out-Null
            $createdTdeCollisionCertificate = $false

            # New databases inherit database-level extended properties from
            # model. The duplicate marker forces sp_addextendedproperty to
            # fail after CREATE DATABASE but before this demo can write its
            # own marker.
            Invoke-Query -Database 'model' -Query @"
EXEC sys.sp_addextendedproperty
    @name = N'DP800_M05_TdeDemoOwnershipToken',
    @value = N'M05 runtime pre-marker collision fixture';
"@ | Out-Null
            $createdTdeMarkerCollision = $true
            $preMarkerFailureOutput = Invoke-SqlScriptExpectFailure -Database 'master' -Path $m05Tde
            if ($preMarkerFailureOutput -notmatch '15233|already exists') {
                Add-Failure 'M05 TDE pre-marker collision did not fail after creating the temporary database.'
            }
            if ((Get-Scalar -Database 'model' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM sys.extended_properties
    WHERE class = 0
      AND name = N'DP800_M05_TdeDemoOwnershipToken'
      AND CONVERT(nvarchar(128), value) = N'M05 runtime pre-marker collision fixture'
) THEN N'PASS' ELSE N'FAIL' END;
"@) -ne 'PASS') {
                Add-Failure 'M05 TDE pre-marker collision fixture was altered or removed.'
            }
            if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN DB_ID(N'$tdeDatabase') IS NULL
                  AND NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$tdeCertificate')
            THEN N'PASS' ELSE N'FAIL' END;
"@) -ne 'PASS') {
                Add-Failure 'M05 TDE pre-marker failure cleanup left a temporary database or certificate behind.'
            }
            $preMarkerDatabaseIdentity = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT database_id
FROM sys.databases
WHERE name = N'$tdeDatabase';
"@
            $preMarkerCertificateThumbprint = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONVERT(varchar(130), thumbprint, 1)
FROM sys.certificates
WHERE name = N'$tdeCertificate';
"@
            Invoke-Query -Database 'model' -Query @"
EXEC sys.sp_dropextendedproperty @name = N'DP800_M05_TdeDemoOwnershipToken';
"@ | Out-Null
            $createdTdeMarkerCollision = $false

            $tdeOutput = Invoke-SqlScript -Database 'master' -Path $m05Tde
            if ($tdeOutput -notmatch '(?s)DP800_M05_TdeDemo.*(?:ENCRYPTION_IN_PROGRESS|ENCRYPTED)') {
                Add-Failure 'M05 TDE demo did not return an encryption-state verification row.'
            }
            if ((Get-Scalar -Database 'master' -Query "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'$tdeDatabase') IS NULL THEN N'PASS' ELSE N'FAIL' END;") -ne 'PASS') {
                Add-Failure "M05 TDE cleanup left $tdeDatabase behind."
            }
            if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$tdeCertificate')
            THEN N'PASS' ELSE N'FAIL' END;
"@) -ne 'PASS') {
                Add-Failure "M05 TDE cleanup left $tdeCertificate behind."
            }
            $expectedMasterKeyIdentity = if ($masterKeyExistedBeforeTde) { $masterKeyIdentityBeforeTde } else { $testMasterKeyIdentity }
            $masterKeyIdentityAfterTde = Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONVERT(nvarchar(36), key_guid)
FROM sys.symmetric_keys
WHERE name = N'##MS_DatabaseMasterKey##';
"@
            if ($masterKeyIdentityAfterTde -ne $expectedMasterKeyIdentity) {
                if ($masterKeyExistedBeforeTde) {
                    Add-Failure 'M05 TDE demo changed or removed the pre-existing master database master key.'
                }
                else {
                    Add-Failure 'M05 TDE demo changed or removed the test-owned master database master key.'
                }
            }
            if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(d.is_encrypted, N':', ISNULL(CONVERT(nvarchar(10), dek.encryption_state), N'NULL'))
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON dek.database_id = d.database_id
WHERE d.name = N'$database';
"@) -ne $adventureGearEncryptionBeforeTde) {
                Add-Failure 'M05 TDE demo changed AdventureGearAI encryption state.'
            }
        }
    }

    Invoke-SqlScript -Database $database -Path $m05Reset | Out-Null
    if ((Get-Scalar -Database $database -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN OBJECT_ID(N'security.SecureCustomers', N'U') IS NULL
                  AND OBJECT_ID(N'security.usp_GetSecureCustomer', N'P') IS NULL
                  AND USER_ID(N'AdventureGearPermissionReader') IS NULL
                  AND (SELECT COUNT(*) FROM customer.Customers) = 120
            THEN N'PASS' ELSE N'FAIL' END;
"@) -ne 'PASS') {
        Add-Failure 'M05 reset removed an unexpected object or left an M05-owned object behind.'
    }
    Invoke-SqlScript -Database $database -Path $m05Common | Out-Null
}
catch {
    Add-Failure $_.Exception.Message
}
finally {
    # Collision fixtures and the temporary master key are deleted only when
    # this invocation created them.
    try {
        if ($createdTdeMarkerCollision) {
            Invoke-Query -Database 'model' -Query @"
EXEC sys.sp_dropextendedproperty @name = N'DP800_M05_TdeDemoOwnershipToken';
"@ | Out-Null
            $createdTdeMarkerCollision = $false
        }
        if ($preMarkerDatabaseIdentity -and (Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT database_id
FROM sys.databases
WHERE name = N'$tdeDatabase';
"@) -eq $preMarkerDatabaseIdentity) {
            Invoke-Query -Database 'master' -Query @"
ALTER DATABASE [$tdeDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$tdeDatabase];
"@ | Out-Null
            $preMarkerDatabaseIdentity = $null
        }
        if ($preMarkerCertificateThumbprint -and (Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CONVERT(varchar(130), thumbprint, 1)
FROM sys.certificates
WHERE name = N'$tdeCertificate';
"@) -eq $preMarkerCertificateThumbprint) {
            Invoke-Query -Database 'master' -Query "DROP CERTIFICATE [$tdeCertificate];" | Out-Null
            $preMarkerCertificateThumbprint = $null
        }
        if ($createdTdeCollisionDatabase) {
            Invoke-Query -Database 'master' -Query @"
ALTER DATABASE [$tdeDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$tdeDatabase];
"@ | Out-Null
            $createdTdeCollisionDatabase = $false
        }
        if ($createdTdeCollisionCertificate) {
            Invoke-Query -Database 'master' -Query "DROP CERTIFICATE [$tdeCertificate];" | Out-Null
            $createdTdeCollisionCertificate = $false
        }
        if ($createdTestMasterKey) {
            $tdeResourcesRemain = (Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN DB_ID(N'$tdeDatabase') IS NOT NULL
                  OR EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$tdeCertificate')
            THEN N'YES' ELSE N'NO' END;
"@) -eq 'YES'
            if ($tdeResourcesRemain) {
                Add-Failure 'M05 TDE test retained its temporary master key because TDE resources were not fully cleaned up.'
            }
            else {
                $masterKeyCleanupStatus = Get-Scalar -Database 'master' -Query @'
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @expectedMasterKeyIdentity uniqueidentifier =
    TRY_CONVERT(uniqueidentifier, N'$(TdeTestMasterKeyIdentity)');
DECLARE @currentMasterKeyIdentity uniqueidentifier;
DECLARE @lockResult int;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC @lockResult = sys.sp_getapplock
        @Resource = N'DP800_M05_TestMasterKeyCleanup',
        @LockMode = N'Exclusive',
        @LockOwner = N'Transaction',
        @LockTimeout = 10000,
        @DbPrincipal = N'public';

    IF @lockResult < 0
    BEGIN
        THROW 51053, 'Could not acquire the TDE test master key cleanup lock.', 1;
    END;

    SELECT @currentMasterKeyIdentity = key_guid
FROM sys.symmetric_keys
    WITH (UPDLOCK, HOLDLOCK)
    WHERE name = N'##MS_DatabaseMasterKey##';

    IF @expectedMasterKeyIdentity IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        SELECT N'MISMATCH' AS CleanupStatus;
    END
    ELSE IF @currentMasterKeyIdentity IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        SELECT N'MISSING' AS CleanupStatus;
    END
    ELSE IF @currentMasterKeyIdentity <> @expectedMasterKeyIdentity
    BEGIN
        ROLLBACK TRANSACTION;
        SELECT N'MISMATCH' AS CleanupStatus;
    END
    ELSE
    BEGIN
        DROP MASTER KEY;
        COMMIT TRANSACTION;
        SELECT N'DROPPED' AS CleanupStatus;
    END
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;
    THROW;
END CATCH;
'@ -SqlCmdVariables @{ TdeTestMasterKeyIdentity = $testMasterKeyIdentity }

                switch ($masterKeyCleanupStatus) {
                    'DROPPED' {
                        if ((Get-Scalar -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM sys.symmetric_keys
    WHERE name = N'##MS_DatabaseMasterKey##'
) THEN N'FAIL' ELSE N'PASS' END;
"@) -ne 'PASS') {
                            Add-Failure 'M05 TDE test-owned master database master key was not removed.'
                        }
                        else {
                            $createdTestMasterKey = $false
                        }
                    }
                    'MISSING' {
                        Add-Failure 'M05 TDE test-owned master database master key is absent; atomic cleanup did not drop an unknown master key.'
                    }
                    'MISMATCH' {
                        Add-Failure 'M05 TDE test-owned master database master key changed; atomic cleanup did not drop a different master key.'
                    }
                    default {
                        Add-Failure "M05 TDE atomic master key cleanup returned unexpected status '$masterKeyCleanupStatus'."
                    }
                }
            }
        }
    }
    catch { Add-Failure "TDE test cleanup failed: $($_.Exception.Message)" }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlcmdPassword, 'Process')
    $testPassword = $null
    $testMasterKeyPassword = $null
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (M03 JSON and M05 security runtime coverage succeeded)' -ForegroundColor Green
exit 0
