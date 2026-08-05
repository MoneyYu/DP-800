[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# ---------------------------------------------------------------------------
# End-to-end runtime validation of the unified AdventureGearAI demo driven only
# through the REAL production manifest and entrypoints (no test sandbox
# manifest). Exercised against a local SQL Server 2025 (mssql2025) container:
#
#   Item 4 - Cumulative M01..M11 via the production runner AND the production
#            bootstrap delegation entrypoint: every module Completes, every
#            representative object/row count is correct, M10 has >= 100 non-null
#            vectors, and the M11 prompt is grounded in canonical data.
#   Item 5 - Independent path: for each module, a full reset back to a fresh
#            core followed by a single direct module request through the
#            production runner auto-applies exactly that module's prerequisites
#            (nothing more) and Completes the requested module.
#
# The suite starts and ends with a full reset, so AdventureGearAI is returned to
# a clean freshly bootstrapped core and no other database is touched. The SA
# password is read from the container and never echoed.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$runnerScript = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$fullResetWrapper = Join-Path $demoRoot 'reset\Reset-AdventureGearAI.ps1'
$m11Prompt = Join-Path $demoRoot 'M11\local\01-build-prompt.sql'

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

# Dependency graph mirrors the production runner (core is an implicit prereq).
$dependencyGraph = @{
    1 = @(); 2 = @(1); 3 = @(1); 4 = @(1); 5 = @(1); 6 = @(1)
    7 = @(1); 8 = @(1); 9 = @(1); 10 = @(1, 9); 11 = @(1, 9, 10)
}
function Get-TransitivePrereqs {
    param([int]$Module)
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    $stack = [System.Collections.Generic.Stack[int]]::new()
    foreach ($d in $dependencyGraph[$Module]) { $stack.Push($d) }
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        if (-not $seen.Add($cur)) { continue }
        foreach ($d in $dependencyGraph[$cur]) { $stack.Push($d) }
    }
    return @($seen)
}

function Invoke-Query {
    param([string]$Database, [string]$Query)
    $result = & $sqlcmd.Source -S $Server -U $User -d $Database -Q $Query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed against '$Database': $($result -join ' ')" }
    return @($result | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
}
function Get-Scalar { param([string]$Query) return (Invoke-Query -Database 'AdventureGearAI' -Query $Query | Select-Object -First 1) }
function Get-Int { param([string]$Query) return [int](Get-Scalar -Query $Query) }
function Get-ModuleStatus { param([int]$Module) return (Get-Scalar -Query "SET NOCOUNT ON; SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber=$Module;") }
function Test-ObjectPresent { param([string]$Object) return ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID('$Object') IS NOT NULL THEN 1 ELSE 0 END;") -eq 1) }
function Assert-Present { param([string]$Object, [string]$Context) if (-not (Test-ObjectPresent -Object $Object)) { Add-Failure "[$Context] expected object '$Object' to be present but it is missing." } }
function Assert-Absent { param([string]$Object, [string]$Context) if (Test-ObjectPresent -Object $Object) { Add-Failure "[$Context] expected object '$Object' to be absent but it is present." } }
function Assert-Count { param([string]$Label, [int]$Actual, [int]$Expected) if ($Actual -ne $Expected) { Add-Failure "$Label is $Actual (expected $Expected)." } }
function Get-DatabaseSet {
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Invoke-Query -Database 'master' -Query 'SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name;'),
        [System.StringComparer]::OrdinalIgnoreCase)
}

# Run a production entrypoint in a subprocess with SQLCMDPASSWORD cleared, so it
# must resolve the password from DP800_SQL_PASSWORD (the documented path). Uses
# -Command so a comma-separated [int[]] -Modules argument binds correctly.
function Invoke-Production {
    param([string]$Script, [int[]]$Modules, [switch]$Force)
    $command = "& '$Script' -Server '$Server' -User '$User'"
    if ($Modules) { $command += " -Modules $($Modules -join ',')" }
    if ($Force) { $command += ' -Force' }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $out = & pwsh -NoProfile -Command $command 2>&1 | Out-String
    $code = $LASTEXITCODE
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    return [pscustomobject]@{ ExitCode = $code; Output = $out }
}
function Invoke-FullReset {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $out = & pwsh -NoProfile -File $fullResetWrapper -Server $Server -User $User 2>&1 | Out-String
    $code = $LASTEXITCODE
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    if ($code -ne 0) { throw "Full reset failed (exit $code). Output: $out" }
}

function Assert-CoreIntact {
    param([string]$Context)
    $checks = [ordered]@{
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
    foreach ($t in $checks.Keys) {
        $c = Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM $t;"
        if ($c -ne $checks[$t]) { Add-Failure "[$Context] canonical core $t count is $c (expected $($checks[$t]))." }
    }
    $canonicalRows = Get-Scalar -Query @"
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
    $schemaCount = Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.schemas WHERE name IN (N'catalog',N'sales',N'customer',N'security',N'ops',N'api',N'search',N'ai');"
    if ($schemaCount -ne 8) { Add-Failure "[$Context] expected 8 domain schemas but found $schemaCount." }
    if ((Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM ops.DemoEnvironment WHERE DemoEnvironmentID=1 AND DatabaseName=N'AdventureGearAI';") -ne 1) {
        Add-Failure "[$Context] ops.DemoEnvironment marker row is missing."
    }
}

# Assert exactly {module + transitive prereqs} are Completed and all others NotStarted.
function Assert-IndependentRun {
    param([int]$Module)
    $expectedCompleted = [System.Collections.Generic.HashSet[int]]::new()
    [void]$expectedCompleted.Add($Module)
    foreach ($p in (Get-TransitivePrereqs -Module $Module)) { [void]$expectedCompleted.Add($p) }
    foreach ($m in 1..11) {
        $status = Get-ModuleStatus -Module $m
        $name = 'M{0:d2}' -f $m
        if ($expectedCompleted.Contains($m)) {
            if ($status -ne 'Completed') { Add-Failure "Independent M$('{0:d2}' -f $Module): expected prerequisite/target $name Completed but got '$status'." }
        }
        else {
            if ($status -ne 'NotStarted') { Add-Failure "Independent M$('{0:d2}' -f $Module): $name should be NotStarted (not a prerequisite) but got '$status'." }
        }
    }
}

Write-Host 'Unified demo production-flow runtime validation (real manifest + entrypoints)'
Write-Host ''

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    $before = Get-DatabaseSet

    # =====================================================================
    # Item 4 - cumulative M01..M11 through the production runner
    # =====================================================================
    Write-Host '--- Item 4: full reset to a fresh core ---'
    Invoke-FullReset
    Assert-CoreIntact -Context 'fresh core'
    foreach ($m in 1..11) { if ((Get-ModuleStatus -Module $m) -ne 'NotStarted') { Add-Failure "Fresh core: M$('{0:d2}' -f $m) is not NotStarted." } }
    Assert-Absent -Object 'catalog.ProductPrice' -Context 'fresh core'
    Assert-Absent -Object 'ops.PerformanceOrders' -Context 'fresh core'
    Assert-Absent -Object 'search.SearchDocuments' -Context 'fresh core'

    Write-Host '--- Item 4: production runner -Modules 1..11 (default manifest) ---'
    $cumulative = Invoke-Production -Script $runnerScript -Modules @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    if ($cumulative.ExitCode -ne 0) { Add-Failure "Cumulative production run exited non-zero. Output: $($cumulative.Output)" }
    if ($cumulative.Output -notmatch 'M01, M02, M03, M04, M05, M06, M07, M08, M09, M10, M11') { Add-Failure "Cumulative run did not report the full dependency-ordered plan. Output: $($cumulative.Output)" }
    foreach ($m in 1..11) { if ((Get-ModuleStatus -Module $m) -ne 'Completed') { Add-Failure "After cumulative run, M$('{0:d2}' -f $m) is not Completed." } }

    Write-Host '--- Item 4: representative objects / counts per module ---'
    # M01
    Assert-Count 'M01 catalog.ProductPrice' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.ProductPrice;') 150
    Assert-Count 'M01 sales.PartitionedOrders' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.PartitionedOrders;') 5
    Assert-Count 'M01 catalog.ProductNode' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.ProductNode;') 150
    if ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN COL_LENGTH('catalog.Products','MetadataFrame') IS NOT NULL THEN 1 ELSE 0 END;") -ne 1) { Add-Failure 'M01 catalog.Products.MetadataFrame computed column is missing.' }
    # M02
    foreach ($obj in 'sales.vw_CustomerOrderSummary', 'sales.fn_OrderTotal', 'sales.usp_AddOrderItem', 'sales.trg_OrderStatusAudit', 'sales.OrderStatusAudit') { Assert-Present -Object $obj -Context 'M02' }
    # M03
    Assert-Count 'M03 ops.EmployeeHierarchy' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.EmployeeHierarchy;') 5
    Assert-Count 'M03 ops.EmployeeNode' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.EmployeeNode;') 5
    Assert-Count 'M03 ops.ReportsTo' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.ReportsTo;') 4
    # M05
    Assert-Count 'M05 security.SecureCustomers' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM security.SecureCustomers;') 120
    Assert-Count 'M05 CustomerRegionPolicy' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.security_policies WHERE name='CustomerRegionPolicy';") 1
    Assert-Count 'M05 AdventureGearMaskedReader' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.database_principals WHERE name='AdventureGearMaskedReader';") 1
    # M06
    Assert-Count 'M06 ops.PerformanceOrders' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') 10000
    Assert-Count 'M06 IX_PerformanceOrders_CustomerDate' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('ops.PerformanceOrders') AND name='IX_PerformanceOrders_CustomerDate';") 1
    if ((Get-Scalar -Query 'SET NOCOUNT ON; SELECT actual_state_desc FROM sys.database_query_store_options;') -ne 'READ_WRITE') { Add-Failure 'M06 Query Store is not in READ_WRITE state.' }
    # M07
    Assert-Present -Object 'catalog.InventoryChangeLog' -Context 'M07'
    Assert-Present -Object 'catalog.usp_LogInventoryChange' -Context 'M07'
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.DeploymentLog;') -lt 1) { Add-Failure 'M07 ops.DeploymentLog must record at least one deployment.' }
    # M08
    Assert-Count 'M08 api.Products view rows' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM api.Products;') 150
    foreach ($obj in 'api.Categories', 'api.ProductCatalog', 'api.InventoryAvailability') { Assert-Present -Object $obj -Context 'M08' }
    if ((Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN (N'ApiProducts', N'ApiCategories');") -ne 0) { Add-Failure 'M08 must not create duplicate Api* tables.' }
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM api.Products v WHERE NOT EXISTS (SELECT 1 FROM catalog.Products p WHERE p.ProductID = v.ProductID);') -ne 0) { Add-Failure 'M08 api.Products must project only canonical catalog.Products rows.' }
    # M09
    Assert-Count 'M09 ai.EmbeddingDocuments' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ai.EmbeddingDocuments;') 500
    # M10: one document for each review/variant pair, all traceable to canonical products.
    $searchRows = Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments;'
    if ($searchRows -ne 5000) { Add-Failure "M10 search.SearchDocuments must have 5000 rows; found $searchRows." }
    $nonNullVectors = Get-Int 'SET NOCOUNT ON; SELECT COUNT(SearchVector) FROM search.SearchDocuments;'
    if ($nonNullVectors -ne 5000) { Add-Failure "M10 must have 5000 non-null vectors; found $nonNullVectors." }
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments WHERE SearchVector IS NULL;') -ne 0) { Add-Failure 'M10 search.SearchDocuments must not contain null vectors.' }
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM search.SearchDocuments d WHERE NOT EXISTS (SELECT 1 FROM catalog.Products p WHERE p.ProductID = d.ProductID);') -ne 0) { Add-Failure 'M10 search.SearchDocuments must derive from canonical catalog.Products.' }
    # M11: prompt builder is grounded in the canonical corpus
    Assert-Present -Object 'ai.usp_BuildRagPrompt' -Context 'M11'
    $ragOutput = & $sqlcmd.Source -S $Server -U $User -d 'AdventureGearAI' -i $m11Prompt -b -C -I 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "M11 prompt builder failed. Output: $ragOutput" }
    if ($ragOutput -notmatch 'Puncture Guard Tire') { Add-Failure "M11 RAG context did not surface the canonical 'Puncture Guard Tire' product. Output: $ragOutput" }
    if ($ragOutput -notmatch 'only from the supplied fictional product-review context') { Add-Failure 'M11 augmented prompt did not include the grounding system instruction.' }

    Assert-CoreIntact -Context 'after cumulative run'

    # =====================================================================
    # Item 4 - cumulative via the production BOOTSTRAP delegation entrypoint
    # =====================================================================
    Write-Host '--- Item 4: bootstrap -Modules delegation entrypoint ---'
    Invoke-FullReset
    $bootstrapDelegated = Invoke-Production -Script $bootstrapScript -Modules @(11)
    if ($bootstrapDelegated.ExitCode -ne 0) { Add-Failure "Bootstrap -Modules 11 delegation exited non-zero. Output: $($bootstrapDelegated.Output)" }
    foreach ($m in 1, 9, 10, 11) { if ((Get-ModuleStatus -Module $m) -ne 'Completed') { Add-Failure "Bootstrap delegation: M$('{0:d2}' -f $m) is not Completed." } }
    foreach ($m in 2, 3, 4, 5, 6, 7, 8) { if ((Get-ModuleStatus -Module $m) -ne 'NotStarted') { Add-Failure "Bootstrap delegation: M$('{0:d2}' -f $m) should be NotStarted." } }
    Assert-Present -Object 'ai.usp_BuildRagPrompt' -Context 'bootstrap delegation'

    # =====================================================================
    # Item 5 - independent path: full reset + single module for every module
    # =====================================================================
    Write-Host '--- Item 5: independent per-module runs from a fresh core ---'
    foreach ($module in 1..11) {
        Invoke-FullReset
        foreach ($m in 1..11) { if ((Get-ModuleStatus -Module $m) -ne 'NotStarted') { Add-Failure "Independent M$('{0:d2}' -f $module): fresh core has M$('{0:d2}' -f $m) not NotStarted." } }
        $run = Invoke-Production -Script $runnerScript -Modules @($module)
        if ($run.ExitCode -ne 0) { Add-Failure "Independent run of M$('{0:d2}' -f $module) exited non-zero. Output: $($run.Output)" }
        Assert-IndependentRun -Module $module
        Assert-CoreIntact -Context "independent M$('{0:d2}' -f $module)"
        Write-Host "  M$('{0:d2}' -f $module): requested module and prerequisites $((@(Get-TransitivePrereqs -Module $module) | Sort-Object | ForEach-Object { 'M{0:d2}' -f $_ }) -join ',') applied."
    }

    # =====================================================================
    # Leave a clean fresh core and confirm isolation.
    # =====================================================================
    Invoke-FullReset
    Assert-CoreIntact -Context 'final fresh core'
    $after = Get-DatabaseSet
    $beforeOthers = @($before | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $afterOthers = @($after | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $diff = Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers
    if ($diff) { Add-Failure "Databases other than AdventureGearAI changed: $(($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')" }
}
finally {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $originalDpPassword, 'Process')
    $password = $null
    [System.GC]::Collect()
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (production-flow cumulative and independent-path runtime checks succeeded)' -ForegroundColor Green
exit 0
