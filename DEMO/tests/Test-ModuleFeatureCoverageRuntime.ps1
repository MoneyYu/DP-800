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

    # The installed legacy sqlcmd splits a -Q argument containing JSON double
    # quotes. An ephemeral UTF-8 input file preserves the SQL batch exactly.
    $inputFile = Join-Path $PSScriptRoot ".Test-ModuleFeatureCoverageRuntime-$PID.sql"
    try {
        [System.IO.File]::WriteAllText(
            $inputFile,
            $Query,
            [System.Text.UTF8Encoding]::new($true)
        )
        $result = & $sqlcmd.Source -S $Server -U $User -d $Database -i $inputFile -h -1 -W -b -C -I -x 2>&1
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed against '$Database': $($result -join ' ')" }
        return @(
            $result |
            ForEach-Object { "$_".Trim() } |
            Where-Object {
                $_ -ne '' -and
                $_ -notmatch '^\(\d+ rows affected\)$' -and
                $_ -notmatch '^Warning:' -and
                $_ -notmatch '^Update mask evaluation will be disabled' -and
                $_ -notmatch '^SQLServerAgent is not currently running'
            }
        )
    }
    finally {
        Remove-Item -LiteralPath $inputFile -Force -ErrorAction SilentlyContinue
    }
}
function Get-Scalar {
    param([string]$Database, [string]$Query)
    return (Invoke-Query -Database $Database -Query $Query | Select-Object -First 1)
}
function Assert-Scalar {
    param([string]$Label, [string]$Expected, [string]$Actual)
    if ($Actual -ne $Expected) { Add-Failure "$Label returned '$Actual' (expected '$Expected')." }
}
function Invoke-ProbeSqlFile {
    param([string]$RelativePath)

    $scriptText = Get-Text $RelativePath
    if ($null -eq $scriptText) { return }

    $scriptText = $scriptText -replace '(?i)USE\s+\[AdventureGearAI\]\s*;', "USE [$probeDatabase];"
    foreach ($batch in ($scriptText -split '(?im)^\s*GO\s*(?:--.*)?(?:\r?\n|$)')) {
        if (-not [string]::IsNullOrWhiteSpace($batch)) {
            Invoke-Query -Database $probeDatabase -Query $batch | Out-Null
        }
    }
}

Write-Host 'SQL Server 2025 module feature coverage (runtime)'
Write-Host ''

# Source setup gates explain the intended RED state before executing any probe.
$bootstrap = Get-Text 'DEMO\bootstrap\01-initialize-adventuregear-demo.sql'
$m01 = @(
    Get-Text 'DEMO\M01\common\01-objects.sql'
    Get-Text 'DEMO\M01\common\02-specialized-tables.sql'
    Get-Text 'DEMO\M01\local\01-inspect.sql'
    Get-Text 'DEMO\M01\local\02-inspect-specialized.sql'
) -join "`n"
$m03 = Get-Text 'DEMO\M03\local\01-advanced-queries.sql'
$m05 = @(
    Get-Text 'DEMO\M05\common\01-security.sql'
    Get-Text 'DEMO\M05\local\01-verify-security.sql'
    Get-Text 'DEMO\M05\local\02-tde-demo.sql'
) -join "`n"
$m06 = @(
    Get-Text 'DEMO\M06\local\01-plans-query-store-dmvs.sql'
    Get-Text 'DEMO\M06\local\07-isolation-rcsi-probe.sql'
    Get-Text 'DEMO\M06\local\08-query-store-plan-forcing.sql'
    Get-Text 'DEMO\M06\local\09-isolation-writer.sql'
    Get-Text 'DEMO\M06\local\10-isolation-reader.sql'
    Get-Text 'DEMO\M06\local\11-enable-rcsi.sql'
    Get-Text 'DEMO\M06\local\12-isolation-rcsi-cleanup.sql'
) -join "`n"
$m08 = Get-Text 'DEMO\M08\common\01-product-api.sql'
$m08Config = Get-Text 'DEMO\M08\common\dab-config.json'
$m09 = Get-Text 'DEMO\M09\common\01-review-data.sql'
$m09Reset = Get-Text 'DEMO\M09\reset\reset.sql'
$m10 = Get-Text 'DEMO\M10\local\01-search.sql'
$m11 = Get-Text 'DEMO\M11\common\01-local-rag.sql'
$m11Azure = Get-Text 'DEMO\M11\azure\01-rag-procedure.sql'

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
Assert-Source $m09 '(?is)compatibility_level.{0,300}IF\s+@compatibilityLevel\s*<\s*170' 'M09 compatibility-level skip'
Assert-Source $m09 '(?i)CREATE\s+TABLE\s+ai\.EmbeddingChunks' 'M09 chunk persistence table'
Assert-Source $m09 '(?i)CROSS\s+APPLY\s+AI_GENERATE_CHUNKS\s*\(\s*SOURCE\s*=' 'M09 chunk generation CROSS APPLY'
Assert-Source $m09 '(?i)ENABLE_CHUNK_SET_ID\s*=\s*1' 'M09 chunk-set IDs'
Assert-Source $m09Reset '(?i)DROP\s+TABLE\s+IF\s+EXISTS\s+ai\.EmbeddingChunks' 'M09 chunk reset'
Assert-Source $m10 '(?i)FREETEXT\s*\(' 'M10 full-text search setup'
Assert-Source $m11 '(?i)FOR\s+JSON\s+PATH\s*,\s*WITHOUT_ARRAY_WRAPPER' 'M11 local JSON single-object context'
Assert-Source $m11Azure '(?i)FOR\s+JSON\s+PATH\s*,\s*WITHOUT_ARRAY_WRAPPER' 'M11 Azure JSON single-object context'
Assert-Source "$m11`n$m11Azure" '(?i)JSON_QUERY\s*\(\s*CONVERT\s*\(\s*nvarchar\s*\(\s*max\s*\)\s*,\s*(?:p\.)?ProductMetadata\s*\)\s*\)' 'M11 nested native json product metadata'

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
                  AND JSON_CONTAINS(Payload, 'road', '$.tags[*]') = 1
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
CREATE TABLE dbo.LedgerProbe (Id int NOT NULL PRIMARY KEY, Value nvarchar(20) NOT NULL) WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);
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
    $engineVersion = Get-Scalar -Database 'master' -Query "SELECT CONVERT(varchar(128), SERVERPROPERTY('ProductVersion'));"
    if ($polyBaseInstalled -eq '1' -or $ftsInstalled -eq '1') {
        foreach ($package in 'mssql-server-fts', 'mssql-server-polybase') {
            $packageVersion = (& docker exec $Container dpkg-query -W "-f=`${Version}" $package 2>$null | Out-String).Trim()
            $packageEngineVersion = $packageVersion -replace '-\d+$', ''
            if ([string]::IsNullOrWhiteSpace($packageVersion)) {
                Add-Failure "$package is not installed in '$Container'."
            }
            elseif ($packageEngineVersion -ne $engineVersion) {
                Add-Failure "$package version '$packageVersion' is not compatible with SQL engine version '$engineVersion'."
            }
            else {
                Write-Host "$package version: $packageVersion (compatible with SQL engine $engineVersion)"
            }
        }
    }
    else {
        Write-Host "SKIP: '$Container' does not use the custom FTS/PolyBase image." -ForegroundColor Yellow
    }

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
ALTER DATABASE CURRENT SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL
);
ALTER DATABASE CURRENT SET ALLOW_SNAPSHOT_ISOLATION ON;
"@ | Out-Null
    Invoke-Query -Database $probeDatabase -Query @"
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
DECLARE @rowCount int;
SELECT @rowCount = COUNT(*) FROM dbo.JsonProbe WHERE Id = 1 /* DP800 feature coverage Query Store probe */;
"@ | Out-Null
    Invoke-Query -Database $probeDatabase -Query @"
EXEC sys.sp_query_store_flush_db;
DECLARE @queryId bigint =
(
    SELECT TOP (1) q.query_id
    FROM sys.query_store_query AS q
    INNER JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE qt.query_sql_text LIKE N'%DP800 feature coverage Query Store probe%'
    ORDER BY q.query_id DESC
);
DECLARE @planId bigint =
(
    SELECT TOP (1) p.plan_id
    FROM sys.query_store_plan AS p
    WHERE p.query_id = @queryId
    ORDER BY p.plan_id DESC
);
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
GO
CREATE OR ALTER PROCEDURE dbo.usp_ProbeEntity AS SELECT COUNT(*) AS ParentCount FROM dbo.ParentProbe;
GO
EXEC sys.sp_cdc_enable_db;
EXEC sys.sp_cdc_enable_table @source_schema=N'dbo', @source_name=N'ChildProbe', @role_name=NULL;
SELECT CASE WHEN OBJECT_ID(N'dbo.usp_ProbeEntity', N'P') IS NOT NULL
                  AND EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(N'dbo.ChildProbe'))
                  AND EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID(N'dbo.ChildProbe'))
            THEN 'PASS' ELSE 'FAIL' END;
EXEC sys.sp_cdc_disable_table @source_schema=N'dbo', @source_name=N'ChildProbe', @capture_instance=N'dbo_ChildProbe';
EXEC sys.sp_cdc_disable_db;
"@ | ForEach-Object { Assert-Scalar -Label 'M08 CDC, relationship, and procedure runtime operations' -Expected 'PASS' -Actual $_ }

    # M09 executes only when the documented compatibility prerequisite exists.
    $compatibilityLevel = [int](Get-Scalar -Database $probeDatabase -Query "SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID();")
    if ($compatibilityLevel -lt 170) {
        Write-Host "SKIP: AI_GENERATE_CHUNKS requires compatibility level 170 (current: $compatibilityLevel)." -ForegroundColor Yellow
    }
    else {
        Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.ChunkProbe
(
    ChunkId bigint IDENTITY CONSTRAINT PK_ChunkProbe PRIMARY KEY,
    SourceProductId int NOT NULL,
    SourceReviewId int NOT NULL,
    ChunkText nvarchar(max) NOT NULL,
    ChunkOrder bigint NOT NULL,
    ChunkOffset bigint NOT NULL,
    ChunkLength int NOT NULL,
    ChunkSetId bigint NOT NULL
);
INSERT dbo.ChunkProbe (SourceProductId, SourceReviewId, ChunkText, ChunkOrder, ChunkOffset, ChunkLength, ChunkSetId)
SELECT source.SourceProductId,
       source.SourceReviewId,
       chunks.chunk,
       chunks.chunk_order,
       chunks.chunk_offset,
       chunks.chunk_length,
       chunks.chunk_set_id
FROM (VALUES
    (101, 1001, CONVERT(nvarchar(max), N'Summit Trail Tire has puncture-resistant casing for rough roads. Riders reported dependable traction and comfortable handling through long wet trail rides.')),
    (102, 1002, CONVERT(nvarchar(max), N'Night Beacon Light keeps the route visible after sunset. The waterproof housing and long battery life helped on repeated evening commutes.'))
) AS source(SourceProductId, SourceReviewId, TextToChunk)
CROSS APPLY AI_GENERATE_CHUNKS
(
    SOURCE = source.TextToChunk,
    CHUNK_TYPE = FIXED,
    CHUNK_SIZE = 40,
    OVERLAP = 10,
    ENABLE_CHUNK_SET_ID = 1
) AS chunks;
-- Fixture: SQL Server LEN excludes trailing spaces, but AI chunk lengths do not.
INSERT dbo.ChunkProbe (SourceProductId, SourceReviewId, ChunkText, ChunkOrder, ChunkOffset, ChunkLength, ChunkSetId)
VALUES (101, 1001, N'Trailing-space chunk ', 1, 1, 21, 1);
SELECT CASE WHEN (SELECT COUNT(*) FROM dbo.ChunkProbe) > 2
                  AND (SELECT COUNT(DISTINCT ChunkSetId) FROM dbo.ChunkProbe) = 2
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.ChunkProbe AS currentChunk
                      WHERE currentChunk.ChunkOrder <> 1
                        AND NOT EXISTS
                        (
                            SELECT 1
                            FROM dbo.ChunkProbe AS priorChunk
                            WHERE priorChunk.ChunkSetId = currentChunk.ChunkSetId
                              AND priorChunk.ChunkOrder = currentChunk.ChunkOrder - 1
                              AND priorChunk.ChunkOffset < currentChunk.ChunkOffset
                        )
                  )
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.ChunkProbe
                      WHERE ChunkLength <> LEN(ChunkText + N'.') - 1 OR ChunkOffset < 1
                  )
            THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M09 chunk rows retain source, order, offset, length, and set identifiers' -Expected 'PASS' -Actual $_ }
    }

    # M10 FREETEXT is conditional on the installed Full-Text Search component.
    if ($ftsInstalled -eq '1') {
        Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.FullTextProbe
(
    FullTextProbeId int IDENTITY CONSTRAINT PK_FullTextProbe PRIMARY KEY,
    Content nvarchar(max) NOT NULL
);
INSERT dbo.FullTextProbe (Content)
VALUES (N'Summit Trail Tire uses puncture-resistant casing for rough roads.');
CREATE FULLTEXT CATALOG ProbeFullTextCatalog;
CREATE FULLTEXT INDEX ON dbo.FullTextProbe(Content LANGUAGE 1033) KEY INDEX PK_FullTextProbe;
ALTER FULLTEXT INDEX ON dbo.FullTextProbe START FULL POPULATION;
WHILE FULLTEXTCATALOGPROPERTY(N'ProbeFullTextCatalog', N'PopulateStatus') <> 0
    WAITFOR DELAY '00:00:01';
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM dbo.FullTextProbe
    WHERE FREETEXT(Content, N'puncture resistance')
) THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M10 FREETEXT runtime operation' -Expected 'PASS' -Actual $_ }
    }
    else {
        Write-Host 'SKIP: FREETEXT requires the Full-Text Search component.' -ForegroundColor Yellow
    }

    # M11 must emit a valid single-object JSON context and a valid prompt while
    # preserving native json product metadata and canonical product identity.
    Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.CanonicalProductProbe
(
    ProductId int NOT NULL PRIMARY KEY,
    ProductName nvarchar(120) NOT NULL,
    ProductMetadata json NOT NULL
);
CREATE TABLE dbo.CanonicalReviewProbe
(
    ReviewId int NOT NULL PRIMARY KEY,
    ProductId int NOT NULL REFERENCES dbo.CanonicalProductProbe(ProductId),
    Rating tinyint NOT NULL,
    ReviewText nvarchar(max) NOT NULL
);
INSERT dbo.CanonicalProductProbe
VALUES (42, N'Summit Trail Tire', '{"category":"Tires","features":["puncture-resistant","wet grip"]}');
INSERT dbo.CanonicalReviewProbe
VALUES (7, 42, 5, N'Puncture resistance stayed dependable over rough roads.');

DECLARE @Reviews nvarchar(max) =
(
    SELECT r.ReviewId, r.Rating, r.ReviewText
    FROM dbo.CanonicalReviewProbe AS r
    WHERE r.ProductId = 42
    FOR JSON PATH
);
DECLARE @Context nvarchar(max) =
(
    SELECT TOP (1)
        p.ProductId,
        p.ProductName,
        JSON_QUERY(CONVERT(nvarchar(max), p.ProductMetadata)) AS ProductMetadata,
        JSON_QUERY(@Reviews) AS Reviews
    FROM dbo.CanonicalProductProbe AS p
    WHERE p.ProductId = 42
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);
DECLARE @Payload nvarchar(max) = JSON_OBJECT
(
    'messages': JSON_ARRAY
    (
        JSON_OBJECT
        (
            'role': 'user',
            'content': CONCAT(N'Context: ', @Context, CHAR(10), N'Question: Which tire resists punctures?')
        )
    )
);
SELECT CASE WHEN ISJSON(@Context) = 1
                  AND ISJSON(@Payload) = 1
                  AND JSON_VALUE(@Context, '$.ProductId') = N'42'
                  AND JSON_VALUE(@Context, '$.ProductName') = N'Summit Trail Tire'
                  AND JSON_VALUE(@Context, '$.ProductMetadata.category') = N'Tires'
                  AND JSON_VALUE(@Context, '$.Reviews[0].ReviewId') = N'7'
                  AND JSON_VALUE(@Payload, '$.messages[0].content') LIKE N'%Summit Trail Tire%'
            THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M11 single-object JSON prompt preserves canonical grounding' -Expected 'PASS' -Actual $_ }

    # Apply the real M09-M11 local scripts twice in dependency order. The probe
    # has just the canonical product/review contract they consume, so this
    # validates cumulative setup and safe reapplication without touching
    # AdventureGearAI.
    Invoke-Query -Database $probeDatabase -Query @"
EXEC(N'CREATE SCHEMA catalog;');
EXEC(N'CREATE SCHEMA customer;');
EXEC(N'CREATE SCHEMA search;');
EXEC(N'CREATE SCHEMA ai;');
CREATE TABLE catalog.Products
(
    ProductID int NOT NULL PRIMARY KEY,
    ProductName nvarchar(120) NOT NULL,
    ProductMetadata json NOT NULL
);
CREATE TABLE customer.ProductReviews
(
    ReviewID int NOT NULL PRIMARY KEY,
    ProductID int NOT NULL REFERENCES catalog.Products(ProductID),
    ReviewTitle nvarchar(200) NOT NULL,
    ReviewText nvarchar(max) NOT NULL,
    Rating tinyint NOT NULL
);
INSERT catalog.Products (ProductID, ProductName, ProductMetadata)
VALUES
    (101, N'Summit Trail Tire', '{"category":"Tires","features":["puncture-resistant","wet grip"]}'),
    (102, N'Night Beacon Light', '{"category":"Lights","features":["waterproof","long battery"]}');
INSERT customer.ProductReviews (ReviewID, ProductID, ReviewTitle, ReviewText, Rating)
VALUES
    (1001, 101, N'Rough-road confidence', N'Puncture resistance and wet traction stayed dependable through long rough trail rides.', 5),
    (1002, 102, N'Visible commute', N'The long battery life kept the route visible for repeated evening commutes.', 5);
"@ | Out-Null

    $m09ToM11LocalScripts = @(
        'DEMO\M09\common\01-review-data.sql',
        'DEMO\M09\local\01-feature-detection.sql',
        'DEMO\M10\common\01-search-data.sql',
        'DEMO\M10\local\01-search.sql',
        'DEMO\M11\common\01-local-rag.sql',
        'DEMO\M11\local\01-build-prompt.sql'
    )
    foreach ($pass in 1..2) {
        foreach ($relativePath in $m09ToM11LocalScripts) {
            Invoke-ProbeSqlFile -RelativePath $relativePath
        }
    }

    if ($compatibilityLevel -ge 170) {
        $chunkPersistenceAssertion = @"
EXISTS (SELECT 1 FROM ai.EmbeddingChunks)
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM ai.EmbeddingChunks AS c
                      WHERE c.ChunkLength <> LEN(c.ChunkText + N'.') - 1
                         OR c.ChunkOffset < 1
                         OR (c.ChunkOrder > 1 AND NOT EXISTS
                             (
                                 SELECT 1
                                 FROM ai.EmbeddingChunks AS prior
                                 WHERE prior.DocumentID = c.DocumentID
                                   AND prior.ChunkSetID = c.ChunkSetID
                                   AND prior.ChunkOrder = c.ChunkOrder - 1
                                   AND prior.ChunkOffset < c.ChunkOffset
                             ))
                  )
"@
    }
    else {
        Write-Host "SKIP: M09 chunk persistence assertion requires compatibility level 170 (current: $compatibilityLevel)." -ForegroundColor Yellow
        $chunkPersistenceAssertion = '1 = 1'
    }

    Invoke-Query -Database $probeDatabase -Query @"
DECLARE @result table (RetrievedContext nvarchar(max), AugmentedPrompt nvarchar(max), LocalDifference nvarchar(max));
INSERT @result EXEC ai.usp_BuildRagPrompt @Question = N'Which tire resists punctures on rough roads?';
SELECT CASE WHEN $chunkPersistenceAssertion
                  AND ISJSON((SELECT TOP (1) RetrievedContext FROM @result)) = 1
                  AND ISJSON((SELECT TOP (1) AugmentedPrompt FROM @result)) = 1
                  AND JSON_VALUE((SELECT TOP (1) RetrievedContext FROM @result), '$.ProductID') = N'101'
                  AND JSON_VALUE((SELECT TOP (1) RetrievedContext FROM @result), '$.ProductMetadata.category') = N'Tires'
                  AND JSON_QUERY((SELECT TOP (1) RetrievedContext FROM @result), '$.Reviews') IS NOT NULL
            THEN 'PASS' ELSE 'FAIL' END;
"@ | ForEach-Object { Assert-Scalar -Label 'M09-M11 cumulative local setup reapplication' -Expected 'PASS' -Actual $_ }
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
