[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# Focused runtime contract for the M01 specialized-table teaching scripts.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$moduleRunner = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$sqlWrapper = Join-Path $demoRoot 'scripts\Invoke-Dp800Sql.ps1'
$resetScript = Join-Path $demoRoot 'M01\reset\reset.sql'
$m08SetupScript = Join-Path $demoRoot 'M08\common\01-product-api.sql'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Add-Failure $Message }
}
function Get-Source {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing source asset: $RelativePath"
        return $null
    }
    return Get-Content -LiteralPath $path -Raw
}
function Get-SourceIndex {
    param([string]$Text, [string]$Value, [switch]$Last)
    if ($null -eq $Text) { return -1 }
    if ($Last) {
        return $Text.LastIndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return $Text.IndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase)
}
function Invoke-Query {
    param([string]$Query)
    $result = & $script:sqlcmd.Source -S $Server -U $User -d AdventureGearAI -Q $Query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed for [$Query]: $($result -join ' ')" }
    return @($result | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
}
function Get-Scalar {
    param([string]$Query)
    return (Invoke-Query -Query $Query | Select-Object -First 1)
}
function Assert-Scalar {
    param([string]$Label, [string]$Expected, [string]$Actual)
    if ($Actual -ne $Expected) { Add-Failure "$Label returned '$Actual' (expected '$Expected')." }
}
function Get-M08CapturePresence {
    return Get-Scalar @"
DECLARE @CaptureExists bit = 0;
IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
    EXEC sys.sp_executesql
        N'SELECT @Exists = CONVERT(bit, CASE WHEN EXISTS
        (
            SELECT 1
            FROM cdc.change_tables
            WHERE source_object_id = OBJECT_ID(N''catalog.Products'')
              AND capture_instance = N''AdventureGearM08Products''
        ) THEN 1 ELSE 0 END);',
        N'@Exists bit OUTPUT',
        @Exists = @CaptureExists OUTPUT;
SELECT CONVERT(varchar(1), @CaptureExists);
"@
}
function Invoke-M01Reset {
    $output = & pwsh -NoProfile -File $sqlWrapper -InputFile $resetScript -Database AdventureGearAI -Server $Server -User $User 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Repository SQL wrapper failed for M01 reset. $($output -join ' ')"
    }
    return ($output -join [Environment]::NewLine)
}
function Invoke-M01Runner {
    param([switch]$Force)
    $output = & pwsh -NoProfile -File $moduleRunner -Modules 1 -Force:$Force -Database AdventureGearAI -Server $Server -User $User 2>&1
    if ($LASTEXITCODE -ne 0) {
        $summary = @($output | Select-Object -Last 30) -join ' '
        throw "Normal M01 module runner (Force=$Force) failed. $summary"
    }
    return ($output -join [Environment]::NewLine)
}
function Invoke-M08Setup {
    $output = & pwsh -NoProfile -File $sqlWrapper -InputFile $m08SetupScript -Database AdventureGearAI -Server $Server -User $User 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Repository SQL wrapper failed for M08 setup. $($output -join ' ')"
    }
}
function Get-CaptureFingerprint {
    param([string]$CaptureInstance)
    return Get-Scalar @"
SELECT CONCAT(
    ct.capture_instance, N'|',
    CONVERT(nvarchar(20), ct.source_object_id), N'|',
    CONVERT(nvarchar(20), cdcTable.object_id), N'|',
    CONVERT(nvarchar(30), cdcTable.create_date, 126))
FROM cdc.change_tables AS ct
JOIN sys.objects AS cdcTable
    ON cdcTable.object_id = OBJECT_ID(N'cdc.' + ct.capture_instance + N'_CT')
WHERE ct.capture_instance = N'$CaptureInstance';
"@
}
function Get-M01CacheFingerprint {
    return Get-Scalar @"
IF OBJECT_ID(N'catalog.ProductCacheInMemory', N'U') IS NULL
    SELECT N'absent|0|null';
ELSE
    EXEC sys.sp_executesql N'
        SELECT CONCAT(
            CONVERT(nvarchar(20), OBJECT_ID(N''catalog.ProductCacheInMemory'')), N''|'',
            CONVERT(nvarchar(20), COUNT(*)), N''|'',
            ISNULL(CONVERT(nvarchar(20), CHECKSUM_AGG(BINARY_CHECKSUM(ProductID, ProductName, CachedAtUtc))), N''null''))
        FROM catalog.ProductCacheInMemory;';
"@
}

$m01Objects = Get-Source 'DEMO\M01\common\01-objects.sql'
$m01Specialized = Get-Source 'DEMO\M01\common\02-specialized-tables.sql'
$m01Reset = Get-Source 'DEMO\M01\reset\reset.sql'

Assert-True ($null -ne $m01Objects -and $m01Objects -match "(?i)JSON_CONTAINS\s*\(\s*ProductMetadata\s*,\s*N'aluminum'\s*,\s*'\$\.frame'\s*\)\s+AS\s+IsAluminumFrame") `
    'M01 JSON_CONTAINS must pass the SQL scalar N''aluminum'' and expose IsAluminumFrame.'
Assert-True ($null -ne $m01Objects -and $m01Objects -notmatch '(?i)JSON_CONTAINS\s*\(\s*ProductMetadata\s*,\s*N''"aluminum"''') `
    'M01 JSON_CONTAINS must not quote the scalar as a JSON string.'

$m01SetupLockAcquire = Get-SourceIndex $m01Specialized 'EXEC @CdcOwnershipLockResult = sys.sp_getapplock'
$m01SetupXtpDdl = Get-SourceIndex $m01Specialized 'CREATE TABLE catalog.ProductCacheInMemory'
$m01SetupStateInvalidation = Get-SourceIndex $m01Specialized 'WHERE ModuleNumber = 8'
$m01SetupNormalRelease = Get-SourceIndex $m01Specialized 'SET @CdcOwnershipLockHeld = 0;' -Last
Assert-True ($m01SetupLockAcquire -ge 0 -and $m01SetupXtpDdl -gt $m01SetupLockAcquire) `
    'M01 specialized setup must acquire the M08 CDC lifecycle lock before XTP DDL.'
Assert-True ($m01SetupStateInvalidation -ge 0 -and $m01SetupNormalRelease -gt $m01SetupXtpDdl -and $m01SetupNormalRelease -gt $m01SetupStateInvalidation) `
    'M01 specialized setup must release the CDC lifecycle lock only after XTP DDL and M08 state invalidation.'
Assert-True ($null -ne $m01Specialized -and $m01Specialized -match '(?is)BEGIN\s+CATCH.*?@CdcOwnershipLockHeld\s*=\s*1.*?sp_releaseapplock.*?THROW') `
    'M01 specialized setup must release a held CDC lifecycle lock on errors.'

$m01ResetLockAcquire = Get-SourceIndex $m01Reset 'EXEC @CdcOwnershipLockResult = sys.sp_getapplock'
$m01ResetXtpDrop = Get-SourceIndex $m01Reset 'DROP TABLE IF EXISTS catalog.ProductCacheInMemory'
$m01ResetStateInvalidation = Get-SourceIndex $m01Reset 'WHERE ModuleNumber IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)'
$m01ResetNormalRelease = Get-SourceIndex $m01Reset 'SET @CdcOwnershipLockHeld = 0;' -Last
Assert-True ($m01ResetLockAcquire -ge 0 -and $m01ResetXtpDrop -gt $m01ResetLockAcquire) `
    'M01 reset must acquire the M08 CDC lifecycle lock before XTP teardown.'
Assert-True ($m01ResetStateInvalidation -ge 0 -and $m01ResetNormalRelease -gt $m01ResetXtpDrop -and $m01ResetNormalRelease -gt $m01ResetStateInvalidation) `
    'M01 reset must release the CDC lifecycle lock only after XTP teardown and dependent state invalidation.'
Assert-True ($null -ne $m01Reset -and $m01Reset -match '(?is)BEGIN\s+CATCH.*?@CdcOwnershipLockHeld\s*=\s*1.*?sp_releaseapplock.*?THROW') `
    'M01 reset must release a held CDC lifecycle lock on errors.'

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

Write-Host 'Focused M01 specialized-table runtime test'
Write-Host ''

$originalSqlCmdPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
$foreignCaptureInstance = 'DP800M01ForeignTest'
$foreignCaptureCreated = $false
$foreignDatabaseCdcEnabledByTest = $false
try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    $bootstrapOutput = & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Core bootstrap failed during M01 test setup.' }

    $coreProductCount = Get-Scalar 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.Products;'
    $canonicalMetadata = Get-Scalar "SET NOCOUNT ON; SELECT CONVERT(nvarchar(max), ProductMetadata) FROM catalog.Products WHERE ProductID = 1;"

    # Full M01 reset -> runner apply -> forced reapply -> reset -> runner
    # reapply lifecycle. The normal runner is the only setup path under test.
    Invoke-M01Reset
    $firstRunOutput = Invoke-M01Runner
    if ($firstRunOutput -notmatch '02-specialized-tables\.sql') {
        Add-Failure "Normal M01 runner did not execute 02-specialized-tables.sql. Output: $firstRunOutput"
    }
    if ($firstRunOutput -notmatch '02-inspect-specialized\.sql') {
        Add-Failure "Normal M01 runner did not execute 02-inspect-specialized.sql. Output: $firstRunOutput"
    }

    Assert-Scalar -Label 'Native json type' -Expected 'json' -Actual (Get-Scalar @"
SELECT TYPE_NAME(user_type_id)
FROM sys.columns
WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'ProductMetadata';
"@)
    Assert-Scalar -Label 'JSON index metadata' -Expected '1' -Actual (Get-Scalar @"
SELECT COUNT(*)
FROM sys.json_indexes
WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'IX_Products_ProductMetadata';
"@)
    Assert-Scalar -Label 'Native JSON predicates' -Expected 'PASS' -Actual (Get-Scalar @"
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM catalog.Products
    WHERE JSON_VALUE(ProductMetadata, '$.frame') IS NOT NULL
      AND JSON_PATH_EXISTS(ProductMetadata, '$.frame') = 1
      AND JSON_CONTAINS(ProductMetadata, N'aluminum', '$.frame') = 1
) THEN 'PASS' ELSE 'FAIL' END;
"@)
    Assert-Scalar -Label 'IsAluminumFrame' -Expected '1' -Actual `
        (Get-Scalar "SELECT JSON_CONTAINS(ProductMetadata, N'aluminum', '$.frame') FROM catalog.Products WHERE ProductID = 1;")
    Assert-Scalar -Label 'Safe native json modify demonstration' -Expected 'M01-safe-modified' -Actual `
        (Get-Scalar "SELECT JSON_VALUE(Payload, '$.lesson') FROM catalog.ProductJsonTeaching WHERE ProductJsonTeachingID = 1;")

    $xtpSupported = Get-Scalar "SELECT CONVERT(varchar(1), SERVERPROPERTY('IsXTPSupported'));"
    if ($xtpSupported -eq '1') {
        Assert-Scalar -Label 'Memory-optimized cache' -Expected '1' -Actual `
            (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'catalog.ProductCacheInMemory') AND is_memory_optimized = 1;")
    }
    else {
        Assert-Scalar -Label 'Memory-optimized cache skipped' -Expected '0' -Actual `
            (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'catalog.ProductCacheInMemory');")
    }

    Assert-Scalar -Label 'Updatable ledger table' -Expected '1' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger') AND ledger_type = 2;")
    Assert-Scalar -Label 'Sequence allocation' -Expected '2' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM catalog.ProductSkuSequenceDemo;")
    Assert-Scalar -Label 'Constraint violation handling' -Expected '4' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM catalog.ProductConstraintViolationLog;")
    Assert-Scalar -Label 'Constraint default application' -Expected '1' -Actual `
        (Get-Scalar "SELECT CONVERT(varchar(1), IsEnabled) FROM catalog.ProductConstraintParent WHERE ProductConstraintParentID = 1;")

    $polyBaseInstalled = Get-Scalar "SELECT CONVERT(varchar(1), SERVERPROPERTY('IsPolyBaseInstalled'));"
    if ($polyBaseInstalled -eq '1') {
        Assert-Scalar -Label 'PolyBase external metadata' -Expected '1' -Actual `
            (Get-Scalar "SELECT COUNT(*) FROM sys.external_tables WHERE object_id = OBJECT_ID(N'catalog.ProductMetadataExternal');")
    }
    else {
        Assert-Scalar -Label 'PolyBase metadata skipped' -Expected '0' -Actual `
            (Get-Scalar "SELECT COUNT(*) FROM sys.external_tables WHERE object_id = OBJECT_ID(N'catalog.ProductMetadataExternal');")
    }

    $forceRunOutput = Invoke-M01Runner -Force
    if ($forceRunOutput -notmatch '02-specialized-tables\.sql') {
        Add-Failure "Forced M01 runner did not re-execute 02-specialized-tables.sql. Output: $forceRunOutput"
    }
    Assert-Scalar -Label 'M01 forced reapply ledger' -Expected '1' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger') AND ledger_type = 2;")

    # Exercise the serialized M08 -> M01 -> M08 lifecycle. A real concurrent
    # collision is nondeterministic; these adjacent transitions prove the state
    # contract at each side of the shared exclusive CDC ownership lock.
    Invoke-M08Setup
    Invoke-Query -Query "UPDATE ops.DemoModuleState SET Status = N'Completed', UpdatedAtUtc = SYSUTCDATETIME() WHERE ModuleNumber = 8;" | Out-Null
    Assert-Scalar -Label 'M08 capture before M01 collision' -Expected '1' -Actual `
        (Get-M08CapturePresence)

    $m01CollisionOutput = Invoke-M01Runner -Force
    if ($m01CollisionOutput -notmatch '02-specialized-tables\.sql') {
        Add-Failure "M01 collision reapply did not execute 02-specialized-tables.sql. Output: $m01CollisionOutput"
    }
    Assert-Scalar -Label 'M01 collision invalidates M08 state' -Expected 'NotStarted' -Actual `
        (Get-Scalar 'SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber = 8;')
    Assert-Scalar -Label 'M01 collision removes M08 capture' -Expected '0' -Actual `
        (Get-M08CapturePresence)

    Invoke-M08Setup
    Invoke-Query -Query "UPDATE ops.DemoModuleState SET Status = N'Completed', UpdatedAtUtc = SYSUTCDATETIME() WHERE ModuleNumber = 8;" | Out-Null
    Assert-Scalar -Label 'M08 reapply after M01 collision' -Expected '1' -Actual `
        (Get-M08CapturePresence)

    Invoke-M01Reset
    Assert-Scalar -Label 'M01 reset preserves core products' -Expected $coreProductCount -Actual `
        (Get-Scalar 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.Products;')
    Assert-Scalar -Label 'M01 reset preserves canonical metadata' -Expected $canonicalMetadata -Actual `
        (Get-Scalar "SET NOCOUNT ON; SELECT CONVERT(nvarchar(max), ProductMetadata) FROM catalog.Products WHERE ProductID = 1;")

    Invoke-M01Runner | Out-Null
    Assert-Scalar -Label 'M01 reapply ledger' -Expected '1' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger') AND ledger_type = 2;")

    # Externally-owned CDC blocks memory-optimized DDL. M01 must preserve both
    # that capture and an existing cache while completing its remaining lessons.
    $foreignCaptureAlreadyExists = Get-Scalar @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
    SELECT COUNT(*) FROM cdc.change_tables WHERE capture_instance = N'$foreignCaptureInstance';
ELSE
    SELECT 0;
"@
    if ($foreignCaptureAlreadyExists -ne '0') {
        throw "The test-owned foreign CDC capture '$foreignCaptureInstance' already exists; refusing to alter it."
    }
    $foreignDatabaseCdcEnabledByTest = (Get-Scalar "SELECT CONVERT(varchar(1), is_cdc_enabled) FROM sys.databases WHERE database_id = DB_ID();") -eq '0'
    if ($foreignDatabaseCdcEnabledByTest) {
        Invoke-Query -Query 'EXEC sys.sp_cdc_enable_db;' | Out-Null
    }
    Invoke-Query -Query @"
EXEC sys.sp_cdc_enable_table
    @source_schema = N'catalog',
    @source_name = N'Products',
    @role_name = NULL,
    @capture_instance = N'$foreignCaptureInstance';
"@ | Out-Null
    $foreignCaptureCreated = $true

    $foreignCaptureBefore = Get-CaptureFingerprint -CaptureInstance $foreignCaptureInstance
    $cacheBefore = Get-M01CacheFingerprint
    $foreignRunOutput = Invoke-M01Runner -Force
    if ($foreignRunOutput -notmatch 'M01 In-Memory OLTP skipped: externally owned CDC remains enabled') {
        Add-Failure "M01 foreign-CDC reapply must report the explicit XTP skip reason. Output: $foreignRunOutput"
    }
    Assert-Scalar -Label 'Foreign CDC capture unchanged after M01 runner' -Expected $foreignCaptureBefore -Actual `
        (Get-CaptureFingerprint -CaptureInstance $foreignCaptureInstance)
    Assert-Scalar -Label 'M01 cache unchanged under foreign CDC' -Expected $cacheBefore -Actual (Get-M01CacheFingerprint)
    Assert-Scalar -Label 'M01 foreign-CDC runner status' -Expected 'Completed' -Actual `
        (Get-Scalar 'SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber = 1;')
    Assert-Scalar -Label 'M01 foreign-CDC ledger' -Expected '1' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger') AND ledger_type = 2;")
    Assert-Scalar -Label 'M01 foreign-CDC JSON teaching table' -Expected '1' -Actual `
        (Get-Scalar 'SELECT COUNT(*) FROM catalog.ProductJsonTeaching;')
    Assert-Scalar -Label 'M01 foreign-CDC sequence results' -Expected '2' -Actual `
        (Get-Scalar 'SELECT COUNT(*) FROM catalog.ProductSkuSequenceDemo;')
    Assert-Scalar -Label 'M01 foreign-CDC constraint results' -Expected '4' -Actual `
        (Get-Scalar 'SELECT COUNT(*) FROM catalog.ProductConstraintViolationLog;')
    $expectedExternalMetadata = if ($polyBaseInstalled -eq '1') { '1' } else { '0' }
    Assert-Scalar -Label 'M01 foreign-CDC external metadata' -Expected $expectedExternalMetadata -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.external_tables WHERE object_id = OBJECT_ID(N'catalog.ProductMetadataExternal');")

    $foreignResetOutput = Invoke-M01Reset
    if ($foreignResetOutput -notmatch 'M01 reset partial: In-Memory OLTP teardown skipped because externally owned CDC remains enabled') {
        Add-Failure "M01 reset under foreign CDC must report the explicit partial-reset reason. Output: $foreignResetOutput"
    }
    Assert-Scalar -Label 'Foreign CDC capture unchanged after M01 reset' -Expected $foreignCaptureBefore -Actual `
        (Get-CaptureFingerprint -CaptureInstance $foreignCaptureInstance)
    Assert-Scalar -Label 'M01 cache preserved by partial reset' -Expected $cacheBefore -Actual (Get-M01CacheFingerprint)
    Assert-Scalar -Label 'M01 partial-reset status' -Expected 'NotStarted' -Actual `
        (Get-Scalar 'SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber = 1;')
    Assert-Scalar -Label 'M01 partial-reset ledger removed' -Expected '0' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger');")
    Assert-Scalar -Label 'M01 partial-reset JSON teaching table removed' -Expected '0' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'catalog.ProductJsonTeaching');")
    Assert-Scalar -Label 'M01 partial-reset sequence results removed' -Expected '0' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'catalog.ProductSkuSequenceDemo');")
    Assert-Scalar -Label 'M01 partial-reset constraint results removed' -Expected '0' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'catalog.ProductConstraintViolationLog');")

    $foreignReapplyOutput = Invoke-M01Runner -Force
    if ($foreignReapplyOutput -notmatch 'M01 In-Memory OLTP skipped: externally owned CDC remains enabled') {
        Add-Failure "M01 reapply after a partial reset must report the explicit XTP skip reason. Output: $foreignReapplyOutput"
    }
    Assert-Scalar -Label 'M01 reapply after partial reset ledger' -Expected '1' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger') AND ledger_type = 2;")
}
catch {
    Add-Failure $_.Exception.Message
}
finally {
    try {
        if ($foreignCaptureCreated) {
            Invoke-Query -Query @"
IF EXISTS (SELECT 1 FROM cdc.change_tables WHERE capture_instance = N'$foreignCaptureInstance')
    EXEC sys.sp_cdc_disable_table
        @source_schema = N'catalog',
        @source_name = N'Products',
        @capture_instance = N'$foreignCaptureInstance';
IF $(if ($foreignDatabaseCdcEnabledByTest) { 1 } else { 0 }) = 1
   AND NOT EXISTS (SELECT 1 FROM cdc.change_tables)
    EXEC sys.sp_cdc_disable_db;
"@ | Out-Null
        }
    }
    catch { Write-Warning "Foreign CDC test cleanup encountered an issue: $($_.Exception.Message)" }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlCmdPassword, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $originalDpPassword, 'Process')
    $password = $null
    [System.GC]::Collect()
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (M01 specialized-table lifecycle succeeded)' -ForegroundColor Green
exit 0
