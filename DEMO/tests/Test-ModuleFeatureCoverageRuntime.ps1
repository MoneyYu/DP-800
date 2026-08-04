[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# Runtime contract for the feature expansion. It never bootstraps, resets, or
# alters AdventureGearAI. All mutable SQL lives in the disposable probe database.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$probeDatabase = 'DP800_FeatureCoverageProbe'
$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Get-Text {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing required source asset: $RelativePath"
        return $null
    }
    return Get-Content -LiteralPath $path -Raw
}
function Assert-Source {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($null -eq $Text -or $Text -notmatch $Pattern) { Add-Failure "Missing feature setup: $Message" }
}

# Follow the repository's runtime-test convention: unavailable prerequisites
# skip cleanly; a reachable local environment reports source gaps as RED tests.
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) { Write-Host 'SKIP: sqlcmd is not available.' -ForegroundColor Yellow; exit 0 }
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) { Write-Host 'SKIP: docker is not available.' -ForegroundColor Yellow; exit 0 }
$running = (& docker ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
if (-not $running) { Write-Host "SKIP: container '$Container' is not running." -ForegroundColor Yellow; exit 0 }
$password = (& docker exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Host "SKIP: MSSQL_SA_PASSWORD is not set in '$Container'." -ForegroundColor Yellow
    exit 0
}

function Invoke-Query {
    param([string]$Database, [string]$Query)
    $result = & $sqlcmd.Source -S $Server -U $User -d $Database -Q $Query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed against '$Database': $($result -join ' ')" }
    return @($result | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
}
function Get-Scalar {
    param([string]$Database, [string]$Query)
    return (Invoke-Query -Database $Database -Query $Query | Select-Object -First 1)
}
function Assert-Scalar {
    param([string]$Label, [string]$Expected, [string]$Actual)
    if ($Actual -ne $Expected) { Add-Failure "$Label returned '$Actual' (expected '$Expected')." }
}

Write-Host 'SQL Server 2025 module feature coverage (runtime)'
Write-Host ''

# Source setup gates explain the intended RED state before executing any probe.
$bootstrap = Get-Text 'DEMO\bootstrap\01-initialize-adventuregear-demo.sql'
$m01 = Get-Text 'DEMO\M01\common\01-objects.sql'
$m03 = Get-Text 'DEMO\M03\local\01-advanced-queries.sql'
$m05 = Get-Text 'DEMO\M05\common\01-security.sql'
$m06 = Get-Text 'DEMO\M06\local\01-plans-query-store-dmvs.sql'
$m08 = Get-Text 'DEMO\M08\common\01-product-api.sql'
$m08Config = Get-Text 'DEMO\M08\common\dab-config.json'
$m09 = Get-Text 'DEMO\M09\common\01-review-data.sql'
$m10 = Get-Text 'DEMO\M10\local\01-search.sql'
$m11 = Get-Text 'DEMO\M11\local\01-build-prompt.sql'

Assert-Source $bootstrap '(?i)ProductMetadata\s+json\b' 'bootstrap native json ProductMetadata column'
Assert-Source $bootstrap '(?i)Preferences\s+json\b' 'bootstrap native json Preferences column'
Assert-Source $bootstrap '(?i)ShippingMetadata\s+json\b' 'bootstrap native json ShippingMetadata column'
Assert-Source $m01 '(?i)CREATE\s+JSON\s+INDEX' 'M01 JSON index setup'
Assert-Source $m01 '(?i)MEMORY_OPTIMIZED\s*=\s*ON' 'M01 memory-optimized table setup'
Assert-Source $m01 '(?i)LEDGER\s*=\s*ON' 'M01 ledger table setup'
Assert-Source $m01 '(?i)CREATE\s+SEQUENCE' 'M01 sequence setup'
Assert-Source $m01 '(?i)(IsPolyBaseInstalled|external table)' 'M01 PolyBase feature detection'
Assert-Source $m03 '(?i)(JSON_ARRAYAGG|JSON_OBJECTAGG)' 'M03 JSON aggregate setup'
Assert-Source $m05 '(?i)default\(\)' 'M05 default() masking setup'
Assert-Source $m06 '(?i)sp_query_store_force_plan' 'M06 Query Store force-plan setup'
Assert-Source $m08 '(?i)sp_cdc_enable' 'M08 CDC setup'
Assert-Source $m08Config '(?i)"cache"\s*:' 'M08 DAB cache configuration'
Assert-Source $m08Config '(?i)"relationships"\s*:' 'M08 DAB relationship configuration'
Assert-Source $m08Config '(?i)"type"\s*:\s*"stored-procedure"' 'M08 DAB stored-procedure entity configuration'
Assert-Source $m09 '(?i)AI_GENERATE_CHUNKS' 'M09 chunk generation setup'
Assert-Source $m10 '(?i)FREETEXT\s*\(' 'M10 full-text search setup'
Assert-Source $m11 '(?i)WITHOUT_ARRAY_WRAPPER' 'M11 JSON single-object setup'

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) missing feature setup item(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')

    # A restricted name, exclusive-access drop, and finally cleanup keep the
    # probe independent from AdventureGearAI and every other database.
    Invoke-Query -Database 'master' -Query @"
IF DB_ID(N'$probeDatabase') IS NOT NULL
BEGIN
    ALTER DATABASE [$probeDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$probeDatabase];
END;
CREATE DATABASE [$probeDatabase];
"@ | Out-Null

    # Native json operations and JSON index.
    Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.JsonProbe (Id int NOT NULL PRIMARY KEY, Payload json NOT NULL);
INSERT dbo.JsonProbe VALUES (1, '{"name":"trail","tags":["road","wet"]}');
CREATE JSON INDEX IX_JsonProbe_Payload ON dbo.JsonProbe(Payload);
UPDATE dbo.JsonProbe SET Payload.modify('$.name', 'summit') WHERE Id = 1;
SELECT CASE WHEN JSON_VALUE(Payload, '$.name') = 'summit'
                  AND JSON_PATH_EXISTS(Payload, '$.tags[0]') = 1
                  AND JSON_CONTAINS(Payload, '"road"', '$.tags') = 1
            THEN 'PASS' ELSE 'FAIL' END
FROM dbo.JsonProbe WHERE Id = 1;
"@ | ForEach-Object { Assert-Scalar -Label 'Native json operations' -Expected 'PASS' -Actual $_ }

    # In-Memory OLTP, Ledger, Sequence, and feature-detected PolyBase/FTS.
    $dataDirectory = Split-Path -Parent (Get-Scalar -Database 'master' -Query "SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID(N'master') AND file_id = 1;")
    $escapedDirectory = $dataDirectory.Replace("'", "''")
    Invoke-Query -Database 'master' -Query @"
ALTER DATABASE [$probeDatabase] ADD FILEGROUP [ProbeMemory] CONTAINS MEMORY_OPTIMIZED_DATA;
ALTER DATABASE [$probeDatabase] ADD FILE (NAME=N'ProbeMemoryFile', FILENAME=N'$escapedDirectory\$probeDatabase`_memory') TO FILEGROUP [ProbeMemory];
"@ | Out-Null
    Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.MemoryProbe (Id int NOT NULL PRIMARY KEY NONCLUSTERED, Value nvarchar(20) NOT NULL) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
CREATE TABLE dbo.LedgerProbe (Id int NOT NULL PRIMARY KEY, Value nvarchar(20) NOT NULL) WITH (LEDGER = ON);
CREATE SEQUENCE dbo.ProbeSequence AS int START WITH 1 INCREMENT BY 1;
INSERT dbo.MemoryProbe VALUES (NEXT VALUE FOR dbo.ProbeSequence, N'memory');
INSERT dbo.LedgerProbe VALUES (1, N'ledger');
SELECT CASE WHEN (SELECT COUNT(*) FROM dbo.MemoryProbe) = 1
                  AND (SELECT COUNT(*) FROM dbo.LedgerProbe) = 1
            THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'Memory optimized, ledger, and sequence operations' -Expected 'PASS' -Actual $_ }
    $polyBaseInstalled = Get-Scalar -Database 'master' -Query "SELECT CONVERT(varchar(1), SERVERPROPERTY('IsPolyBaseInstalled'));"
    $ftsInstalled = Get-Scalar -Database 'master' -Query "SELECT CONVERT(varchar(1), FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'));"
    Write-Host "PolyBase installed: $polyBaseInstalled; Full-Text installed: $ftsInstalled"

    # M03 JSON output/aggregate/shredding, plus M11 single-object JSON output.
    Invoke-Query -Database $probeDatabase -Query @"
DECLARE @json json = '{"items":[{"name":"trail"},{"name":"summit"}]}';
DECLARE @array nvarchar(max) = (SELECT JSON_ARRAYAGG([value]) FROM OPENJSON(@json, '$.items') WITH ([value] nvarchar(30) '$.name'));
DECLARE @object nvarchar(max) = (SELECT 1 AS id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
SELECT CASE WHEN @array LIKE '%trail%' AND @object LIKE '%"id":1%' THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M03/M11 JSON runtime operations' -Expected 'PASS' -Actual $_ }

    # M05 masking and object-level permissions; the TDE certificate is isolated
    # under the probe name in master and is removed with the probe.
    Invoke-Query -Database 'master' -Query @"
CREATE CERTIFICATE [DP800_FeatureCoverageProbeCertificate]
WITH SUBJECT = N'DP800 feature coverage probe';
"@ | Out-Null
    Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.MaskingProbe (Id int PRIMARY KEY, Secret nvarchar(50) MASKED WITH (FUNCTION = 'default()'));
CREATE USER ProbeReader WITHOUT LOGIN;
GRANT SELECT ON OBJECT::dbo.MaskingProbe TO ProbeReader;
DENY UPDATE ON OBJECT::dbo.MaskingProbe TO ProbeReader;
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE [DP800_FeatureCoverageProbeCertificate];
ALTER DATABASE CURRENT SET ENCRYPTION ON;
SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id = USER_ID(N'ProbeReader'))
                  AND EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE encryption_state IN (2,3))
            THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M05 masking, permissions, and TDE runtime operations' -Expected 'PASS' -Actual $_ }

    # M06 isolation and Query Store force/unforce lifecycle.
    Invoke-Query -Database $probeDatabase -Query @"
ALTER DATABASE CURRENT SET QUERY_STORE = ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
SELECT COUNT(*) FROM dbo.JsonProbe WHERE Id = 1;
DECLARE @queryId bigint = (SELECT TOP (1) q.query_id FROM sys.query_store_query AS q ORDER BY q.query_id DESC);
DECLARE @planId bigint = (SELECT TOP (1) p.plan_id FROM sys.query_store_plan AS p WHERE p.query_id = @queryId ORDER BY p.plan_id DESC);
IF @queryId IS NOT NULL AND @planId IS NOT NULL
BEGIN
    EXEC sys.sp_query_store_force_plan @query_id = @queryId, @plan_id = @planId;
    EXEC sys.sp_query_store_unforce_plan @query_id = @queryId, @plan_id = @planId;
END;
SELECT CASE WHEN @queryId IS NOT NULL AND @planId IS NOT NULL THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M06 isolation and Query Store lifecycle' -Expected 'PASS' -Actual $_ }

    # M08 CDC, relationship, and stored-procedure source shape.
    Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.ParentProbe (Id int NOT NULL PRIMARY KEY);
CREATE TABLE dbo.ChildProbe (Id int NOT NULL PRIMARY KEY, ParentId int NOT NULL REFERENCES dbo.ParentProbe(Id));
CREATE OR ALTER PROCEDURE dbo.usp_ProbeEntity AS SELECT COUNT(*) AS ParentCount FROM dbo.ParentProbe;
EXEC sys.sp_cdc_enable_db;
EXEC sys.sp_cdc_enable_table @source_schema=N'dbo', @source_name=N'ChildProbe', @role_name=NULL;
SELECT CASE WHEN OBJECT_ID(N'dbo.usp_ProbeEntity', N'P') IS NOT NULL
                  AND EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(N'dbo.ChildProbe'))
                  AND EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID(N'dbo.ChildProbe'))
            THEN 'PASS' ELSE 'FAIL' END;
EXEC sys.sp_cdc_disable_table @source_schema=N'dbo', @source_name=N'ChildProbe', @capture_instance=N'dbo_ChildProbe';
EXEC sys.sp_cdc_disable_db;
"@ | ForEach-Object { Assert-Scalar -Label 'M08 CDC, relationship, and procedure runtime operations' -Expected 'PASS' -Actual $_ }

    # M09 chunk persistence and M10 FREETEXT are conditional on installed engine features.
    Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.ChunkProbe (ChunkId int IDENTITY CONSTRAINT PK_ChunkProbe PRIMARY KEY, ChunkText nvarchar(max) NOT NULL);
INSERT dbo.ChunkProbe (ChunkText)
SELECT chunks.chunk
FROM (VALUES (N'Trail riding requires careful tire selection.')) AS source(TextToChunk)
CROSS APPLY AI_GENERATE_CHUNKS(SOURCE = source.TextToChunk, CHUNK_TYPE = FIXED, CHUNK_SIZE = 20, OVERLAP = 0) AS chunks;
CREATE FULLTEXT CATALOG ProbeFullTextCatalog;
CREATE FULLTEXT INDEX ON dbo.ChunkProbe(ChunkText LANGUAGE 1033) KEY INDEX PK_ChunkProbe;
ALTER FULLTEXT INDEX ON dbo.ChunkProbe START FULL POPULATION;
WAITFOR DELAY '00:00:02';
SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.ChunkProbe WHERE FREETEXT(ChunkText, N'tire')) THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M09 chunks and M10 FREETEXT runtime operations' -Expected 'PASS' -Actual $_ }
}
catch {
    Add-Failure "Runtime feature probe failed: $($_.Exception.Message)"
}
finally {
    try {
        Invoke-Query -Database 'master' -Query @"
IF DB_ID(N'$probeDatabase') IS NOT NULL
BEGIN
    ALTER DATABASE [$probeDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$probeDatabase];
END;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'DP800_FeatureCoverageProbeCertificate')
    DROP CERTIFICATE [DP800_FeatureCoverageProbeCertificate];
"@ | Out-Null
    }
    catch {
        Add-Failure "Probe cleanup failed for ${probeDatabase}: $($_.Exception.Message)"
    }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    $password = $null
    [System.GC]::Collect()
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all SQL Server 2025 feature probes succeeded)' -ForegroundColor Green
exit 0
