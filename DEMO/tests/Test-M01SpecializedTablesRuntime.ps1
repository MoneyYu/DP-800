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
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
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
function Invoke-M01Reset {
    $output = & pwsh -NoProfile -File $sqlWrapper -InputFile $resetScript -Database AdventureGearAI -Server $Server -User $User 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Repository SQL wrapper failed for M01 reset. $($output -join ' ')"
    }
}
function Invoke-M01Runner {
    param([switch]$Force)
    $output = & pwsh -NoProfile -File $moduleRunner -Modules 1 -Force:$Force -Database AdventureGearAI -Server $Server -User $User 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Normal M01 module runner failed. $($output -join ' ')"
    }
    return ($output -join [Environment]::NewLine)
}

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

    Invoke-M01Reset
    Assert-Scalar -Label 'M01 reset preserves core products' -Expected $coreProductCount -Actual `
        (Get-Scalar 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.Products;')
    Assert-Scalar -Label 'M01 reset preserves canonical metadata' -Expected $canonicalMetadata -Actual `
        (Get-Scalar "SET NOCOUNT ON; SELECT CONVERT(nvarchar(max), ProductMetadata) FROM catalog.Products WHERE ProductID = 1;")

    Invoke-M01Runner | Out-Null
    Assert-Scalar -Label 'M01 reapply ledger' -Expected '1' -Actual `
        (Get-Scalar "SELECT COUNT(*) FROM sys.tables WHERE object_id = OBJECT_ID(N'ops.InventoryLedger') AND ledger_type = 2;")
}
catch {
    Add-Failure $_.Exception.Message
}
finally {
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
