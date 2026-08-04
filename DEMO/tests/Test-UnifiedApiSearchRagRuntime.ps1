[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Focused runtime integration test for the migrated M07-M11 modules. It drives
# the real production setup scripts through the dependency-aware runner against a
# freshly bootstrapped AdventureGearAI database and asserts the domain-schema
# behavior (API views, search corpus, RAG context). A test-local sandbox manifest
# references the real M07-M11 scripts plus a no-op for the M01 prerequisite (owned
# by another agent), so the production manifest and M01-M06 files are untouched.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$scriptsRoot = Join-Path $demoRoot 'scripts'
$runnerScript = Join-Path $scriptsRoot 'Invoke-DemoModule.ps1'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$sandboxRoot = Join-Path $PSScriptRoot '.apisearchrag-sandbox'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

# --- Preconditions: skip (do not fail) when the environment is unavailable ------
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) { Write-Host 'SKIP: sqlcmd is not available.' -ForegroundColor Yellow; exit 0 }
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) { Write-Host 'SKIP: docker is not available.' -ForegroundColor Yellow; exit 0 }
$running = (& docker ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
if (-not $running) { Write-Host "SKIP: container '$Container' is not running." -ForegroundColor Yellow; exit 0 }
$password = (& docker exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($password)) { Write-Host "SKIP: MSSQL_SA_PASSWORD is not set in '$Container'." -ForegroundColor Yellow; exit 0 }

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
function Get-DatabaseSet {
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Invoke-Query -Database 'master' -Query 'SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name;'),
        [System.StringComparer]::OrdinalIgnoreCase)
}
function Get-ModuleStatus {
    param([int]$Module)
    return Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber=$Module;"
}
function Assert-CanonicalCore {
    param([string]$Context)
    $expectedCounts = [ordered]@{
        'catalog.Categories'      = 10
        'catalog.Products'        = 150
        'catalog.Inventory'       = 150
        'customer.Customers'      = 120
        'customer.ProductReviews' = 500
        'sales.Orders'            = 800
        'sales.OrderItems'        = 2400
        'ops.DemoModuleState'     = 11
        'ops.DemoEnvironment'     = 1
    }
    foreach ($table in $expectedCounts.Keys) {
        $actual = [int](Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM $table;")
        if ($actual -ne $expectedCounts[$table]) {
            Add-Failure "[$Context] canonical core $table count is $actual (expected $($expectedCounts[$table]))."
        }
    }
    $canonicalRows = Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(
    (SELECT ProductName FROM catalog.Products WHERE ProductID = 1), N'|',
    (SELECT ProductName FROM catalog.Products WHERE ProductID = 4), N'|',
    (SELECT CustomerName FROM customer.Customers WHERE CustomerID = 3)
);
"@
    if ($canonicalRows -ne 'Trailblazer 29 Bike|Puncture Guard Tire|Jordan Patel') {
        Add-Failure "[$Context] canonical seed rows changed: '$canonicalRows'."
    }
}

Write-Host 'Unified API/search/RAG (M07-M11) runtime integration test'
Write-Host ''

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
$testedModules = @(1, 7, 8, 9, 10, 11)
$stateSnapshot = @{}

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

    $before = Get-DatabaseSet
    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Core bootstrap failed during test setup.' }
    Assert-CanonicalCore -Context 'after bootstrap'

    # Snapshot the tested module rows so we can restore them exactly afterward.
    foreach ($module in $testedModules) {
        $stateSnapshot[$module] = Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(
    Status, '~',
    ISNULL(CONVERT(nvarchar(30), StartedAtUtc, 126), ''), '~',
    ISNULL(CONVERT(nvarchar(30), CompletedAtUtc, 126), ''), '~',
    ISNULL(REPLACE(LastError, '~', ' '), ''))
FROM ops.DemoModuleState WHERE ModuleNumber=$module;
"@
    }

    # Reset tested module state to a NotStarted baseline for the scenario.
    Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'NotStarted', StartedAtUtc=NULL, CompletedAtUtc=NULL, LastError=NULL, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber IN (1,7,8,9,10,11);" | Out-Null

    # A no-op stands in for the M01 prerequisite (owned by another agent). The
    # real M07-M11 scripts are referenced via relative paths from the sandbox.
    $noop = Join-Path $sandboxRoot 'noop-m01.sql'
    Set-Content -LiteralPath $noop -Value "SET NOCOUNT ON;`r`nPRINT N'M01 prerequisite no-op for the API/search/RAG runtime test';" -NoNewline

    $sandboxManifest = @{
        schemaVersion = '1.0.0'
        modules = @(
            @{ module = 1;  ready = $true; setup = @{ common = @('noop-m01.sql'); local = @(); azure = @() } }
            @{ module = 7;  ready = $true; setup = @{ common = @('../../M07/common/01-inventory-deployment-log.sql'); local = @(); azure = @() } }
            @{ module = 8;  ready = $true; setup = @{ common = @('../../M08/common/01-product-api.sql'); local = @(); azure = @() } }
            @{ module = 9;  ready = $true; setup = @{ common = @('../../M09/common/01-review-data.sql'); local = @('../../M09/local/01-feature-detection.sql'); azure = @('../../M09/azure/01-external-model.sql') } }
            @{ module = 10; ready = $true; setup = @{ common = @('../../M10/common/01-search-data.sql'); local = @('../../M10/local/01-search.sql'); azure = @('../../M10/azure/01-ann-search.sql') } }
            @{ module = 11; ready = $true; setup = @{ common = @('../../M11/common/01-local-rag.sql'); local = @('../../M11/local/01-build-prompt.sql'); azure = @('../../M11/azure/01-rag-procedure.sql') } }
        )
    }
    $manifestPath = Join-Path $sandboxRoot 'manifest.json'
    Set-Content -LiteralPath $manifestPath -Value ($sandboxManifest | ConvertTo-Json -Depth 8) -NoNewline

    # --- Scenario A: cumulative M07-M11 resolves M01 first and all Complete ----
    # pwsh -File cannot bind a multi-value array parameter, so drive the runner
    # via -Command where the comma array parses correctly.
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $cumCommand = "& '$runnerScript' -Server '$Server' -User '$User' -Modules 7,8,9,10,11 -ManifestPath '$manifestPath'"
    $cumOutput = & pwsh -NoProfile -Command $cumCommand 2>&1 | Out-String
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    if ($LASTEXITCODE -ne 0) { Add-Failure "Cumulative M07-M11 run exited non-zero. Output: $cumOutput" }
    if ($cumOutput -notmatch 'M01, M07, M08, M09, M10, M11') { Add-Failure "Cumulative run did not report plan M01,M07..M11. Output: $cumOutput" }
    foreach ($module in 1, 7, 8, 9, 10, 11) {
        $status = Get-ModuleStatus -Module $module
        if ($status -ne 'Completed') { Add-Failure "After cumulative run, M$('{0:d2}' -f $module) status is '$status' (expected Completed)." }
    }

    # --- M08: api.* views exist and project catalog data (no duplicate tables) -
    $apiProductsRows = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM api.Products;')
    if ($apiProductsRows -ne 150) { Add-Failure "api.Products view returned $apiProductsRows rows (expected 150)." }
    $catalogMatch = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM api.Products v WHERE NOT EXISTS (SELECT 1 FROM catalog.Products p WHERE p.ProductID = v.ProductID);')
    if ($catalogMatch -ne 0) { Add-Failure "api.Products must project only canonical catalog.Products rows ($catalogMatch orphan rows)." }
    $dupTables = [int](Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN (N'ApiProducts', N'ApiCategories');")
    if ($dupTables -ne 0) { Add-Failure "Duplicate Api* tables must not exist after migration ($dupTables found)." }

    # --- M09/M10: review documents and review/variant search corpus -----------
    $embeddingRows = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM ai.EmbeddingDocuments;')
    if ($embeddingRows -ne 500) { Add-Failure "ai.EmbeddingDocuments has $embeddingRows rows (expected 500)." }
    $searchRows = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments;')
    if ($searchRows -ne 5000) { Add-Failure "search.SearchDocuments must have 5000 rows; found $searchRows." }
    $nullVectors = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments WHERE SearchVector IS NULL;')
    if ($nullVectors -ne 0) { Add-Failure "search.SearchDocuments must have non-null vectors; found $nullVectors null vectors." }
    $searchOrphans = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments d WHERE NOT EXISTS (SELECT 1 FROM catalog.Products p WHERE p.ProductID = d.ProductID);')
    if ($searchOrphans -ne 0) { Add-Failure "search.SearchDocuments must derive from canonical catalog.Products ($searchOrphans orphan rows)." }

    # --- M11: RAG context comes from the canonical products/reviews -----------
    # The search corpus M11 retrieves from must be fully traceable to the
    # canonical catalog.Products and customer.ProductReviews.
    $ragTraceable = [int](Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments d INNER JOIN customer.ProductReviews r ON r.ProductID = d.ProductID INNER JOIN catalog.Products p ON p.ProductID = d.ProductID WHERE p.ProductName LIKE N'%Tire%';")
    if ($ragTraceable -lt 1) { Add-Failure 'M11/M10 search corpus must be traceable to catalog.Products and customer.ProductReviews.' }
    # Executing the local prompt builder returns context grounded in a canonical product.
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    $ragOutput = & $sqlcmd.Source -S $Server -U $User -d 'AdventureGearAI' -i (Join-Path $demoRoot 'M11\local\01-build-prompt.sql') -b -C -I 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "M11 local prompt builder failed. Output: $ragOutput" }
    if ($ragOutput -notmatch 'Puncture Guard Tire') { Add-Failure "M11 RAG context did not surface the canonical 'Puncture Guard Tire' product. Output: $ragOutput" }

    # --- Scenario B: rerun without -Force skips Completed modules --------------
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $rerunOutput = & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 11 -ManifestPath $manifestPath 2>&1 | Out-String
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    if ($LASTEXITCODE -ne 0) { Add-Failure "Rerun (M11) exited non-zero. Output: $rerunOutput" }
    if ($rerunOutput -notmatch 'already Completed; skipping') { Add-Failure "Rerun should skip Completed modules. Output: $rerunOutput" }

    # --- Scenario C: -Force re-runs the resolved M11 dependency chain ----------
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $forceOutput = & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 11 -Force -ManifestPath $manifestPath 2>&1 | Out-String
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    if ($LASTEXITCODE -ne 0) { Add-Failure "Force rerun (M11) exited non-zero. Output: $forceOutput" }
    foreach ($module in 1, 9, 10, 11) {
        $status = Get-ModuleStatus -Module $module
        if ($status -ne 'Completed') { Add-Failure "After -Force, M$('{0:d2}' -f $module) status is '$status' (expected Completed)." }
    }
    # Idempotent re-seed preserves every review/variant search document.
    $searchRowsAfterForce = [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments;')
    if ($searchRowsAfterForce -ne 5000) { Add-Failure "After -Force re-seed, search.SearchDocuments has $searchRowsAfterForce rows (expected 5000)." }

    # --- Isolation: only AdventureGearAI may differ; no other DB touched ------
    $after = Get-DatabaseSet
    $beforeOthers = @($before | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $afterOthers = @($after | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $diff = Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers
    if ($diff) { Add-Failure "Databases other than AdventureGearAI changed: $(( $diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')" }
}
finally {
    # Restore module state exactly for the tested modules.
    try {
        foreach ($module in $testedModules) {
            if (-not $stateSnapshot.ContainsKey($module)) { continue }
            $parts = "$($stateSnapshot[$module])".Split('~')
            $status = if ($parts[0]) { $parts[0] } else { 'NotStarted' }
            $started = if ($parts.Count -gt 1 -and $parts[1]) { "'" + $parts[1] + "'" } else { 'NULL' }
            $completed = if ($parts.Count -gt 2 -and $parts[2]) { "'" + $parts[2] + "'" } else { 'NULL' }
            $lastError = if ($parts.Count -gt 3 -and $parts[3]) { "N'" + ($parts[3] -replace "'", "''") + "'" } else { 'NULL' }
            Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'$status', StartedAtUtc=$started, CompletedAtUtc=$completed, LastError=$lastError, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber=$module;" | Out-Null
        }
    }
    catch { Write-Warning "State restore encountered an issue: $($_.Exception.Message)" }

    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $originalDpPassword, 'Process')
    $password = $null
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (M07-M11 runtime integration checks succeeded)' -ForegroundColor Green
exit 0
