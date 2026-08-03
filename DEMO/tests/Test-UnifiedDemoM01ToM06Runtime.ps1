[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# ---------------------------------------------------------------------------
# Focused runtime integration for the migrated M01-M06 demos. It exercises the
# real production module scripts through the hybrid runner + manifest against a
# local SQL Server 2025 (mssql2025) container:
#   * cumulative M01..M06 run
#   * each module independently from the core (prerequisite-aware)
#   * rerun without -Force is a no-op, -Force safely re-applies
#   * expected objects / row counts
#   * canonical data and other databases are left unchanged
# The password is taken from the container and never echoed. Module state rows
# 1-6 are snapshotted and restored, so the database is returned to a known
# core+modules state and no other database is touched.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$runnerScript = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'

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
function Get-Int {
    param([string]$Query)
    return [int](Get-Scalar -Database 'AdventureGearAI' -Query $Query)
}
function Get-ModuleStatus {
    param([int]$Module)
    return Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber=$Module;"
}
function Get-DatabaseSet {
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Invoke-Query -Database 'master' -Query 'SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name;'),
        [System.StringComparer]::OrdinalIgnoreCase)
}
# Runs the hybrid runner in a subprocess with SQLCMDPASSWORD cleared, so the
# runner must resolve the password from DP800_SQL_PASSWORD (the documented path).
function Invoke-Runner {
    param([int[]]$Modules, [switch]$Force)
    $moduleArg = ($Modules -join ',')
    $command = "& '$runnerScript' -Server '$Server' -User '$User' -Modules $moduleArg"
    if ($Force) { $command += ' -Force' }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $out = & pwsh -NoProfile -Command $command 2>&1 | Out-String
    $code = $LASTEXITCODE
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    return [pscustomobject]@{ ExitCode = $code; Output = $out }
}
function Assert-Count {
    param([string]$Label, [int]$Actual, [int]$Expected)
    if ($Actual -ne $Expected) { Add-Failure "$Label is $Actual (expected $Expected)." }
}

Write-Host 'Focused M01-M06 runtime integration test'
Write-Host ''

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
$modules = @(1, 2, 3, 4, 5, 6)
$stateSnapshot = @{}

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    # Ensure the AdventureGearAI core exists (idempotent) and snapshot state.
    $before = Get-DatabaseSet
    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Core bootstrap failed during test setup.' }

    foreach ($module in $modules) {
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

    # Canonical baseline that the exercises must NOT mutate (they roll back).
    $ordersBefore = Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.Orders;'
    $orderItemsBefore = Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.OrderItems;'
    $order3Before = Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT OrderStatus FROM sales.Orders WHERE OrderID=3;'

    # Reset the M01-M06 state rows to a NotStarted baseline for the scenario.
    Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'NotStarted', StartedAtUtc=NULL, CompletedAtUtc=NULL, LastError=NULL, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber IN (1,2,3,4,5,6);" | Out-Null

    # --- Scenario A: cumulative M01..M06 run ---------------------------------
    $runA = Invoke-Runner -Modules $modules
    if ($runA.ExitCode -ne 0) { Add-Failure "Cumulative M01-M06 run exited non-zero. Output: $($runA.Output)" }
    foreach ($module in $modules) {
        $status = Get-ModuleStatus -Module $module
        if ($status -ne 'Completed') { Add-Failure "After cumulative run, M$('{0:d2}' -f $module) status is '$status' (expected Completed)." }
    }

    # --- Expected objects / row counts ---------------------------------------
    Assert-Count 'catalog.ProductPrice count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.ProductPrice;') 12
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.ProductPriceHistory;') -lt 1) { Add-Failure 'catalog.ProductPriceHistory should contain at least one historical row.' }
    if ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN COL_LENGTH('catalog.Products','MetadataFrame') IS NOT NULL THEN 1 ELSE 0 END;") -ne 1) { Add-Failure 'catalog.Products.MetadataFrame computed column is missing.' }
    Assert-Count 'IX_Products_MetadataFrame' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('catalog.Products') AND name='IX_Products_MetadataFrame';") 1
    Assert-Count 'sales.PartitionedOrders count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.PartitionedOrders;') 5
    Assert-Count 'catalog.ProductNode count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.ProductNode;') 12
    Assert-Count 'catalog.ProductRelatedTo count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM catalog.ProductRelatedTo;') 3

    foreach ($obj in 'sales.vw_CustomerOrderSummary', 'sales.fn_OrderTotal', 'sales.fn_CustomerOrders', 'sales.usp_AddOrderItem', 'sales.trg_OrderStatusAudit', 'sales.OrderStatusAudit') {
        if ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID('$obj') IS NOT NULL THEN 1 ELSE 0 END;") -ne 1) { Add-Failure "Expected M02 object is missing: $obj" }
    }
    # The M02 exercise rolls back, so its audit sink is empty afterward.
    Assert-Count 'sales.OrderStatusAudit count (rolled back)' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.OrderStatusAudit;') 0

    Assert-Count 'ops.EmployeeHierarchy count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.EmployeeHierarchy;') 5
    Assert-Count 'ops.EmployeeNode count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.EmployeeNode;') 5
    Assert-Count 'ops.ReportsTo count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.ReportsTo;') 4

    Assert-Count 'security.SecureCustomers count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM security.SecureCustomers;') 6
    Assert-Count 'security.CustomerRegionPolicy' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.security_policies WHERE name='CustomerRegionPolicy';") 1
    Assert-Count 'AdventureGearMaskedReader user' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.database_principals WHERE name='AdventureGearMaskedReader';") 1
    Assert-Count 'AdventureGearWestReader user' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.database_principals WHERE name='AdventureGearWestReader';") 1

    Assert-Count 'ops.PerformanceOrders count' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') 10000
    Assert-Count 'IX_PerformanceOrders_CustomerDate' (Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('ops.PerformanceOrders') AND name='IX_PerformanceOrders_CustomerDate';") 1
    if ((Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT actual_state_desc FROM sys.database_query_store_options;') -ne 'READ_WRITE') { Add-Failure 'Query Store is not in READ_WRITE state.' }

    # --- Scenario B: rerun without -Force is a no-op --------------------------
    $runB = Invoke-Runner -Modules $modules
    if ($runB.ExitCode -ne 0) { Add-Failure "Rerun without -Force exited non-zero. Output: $($runB.Output)" }
    if ($runB.Output -notmatch 'already Completed; skipping') { Add-Failure 'Rerun without -Force should skip Completed modules.' }
    Assert-Count 'ops.PerformanceOrders after no-op rerun' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') 10000

    # --- Scenario C: -Force safely re-applies (idempotent) -------------------
    $runC = Invoke-Runner -Modules $modules -Force
    if ($runC.ExitCode -ne 0) { Add-Failure "Force rerun exited non-zero. Output: $($runC.Output)" }
    foreach ($module in $modules) {
        if ((Get-ModuleStatus -Module $module) -ne 'Completed') { Add-Failure "After -Force, M$('{0:d2}' -f $module) is not Completed." }
    }
    Assert-Count 'ops.PerformanceOrders after -Force (idempotent)' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') 10000
    Assert-Count 'security.SecureCustomers after -Force (idempotent)' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM security.SecureCustomers;') 6
    Assert-Count 'sales.PartitionedOrders after -Force (idempotent)' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.PartitionedOrders;') 5

    # --- Scenario D: each module runs independently from the core -------------
    # Reset M05 and M06 to NotStarted and run them one at a time; the runner must
    # resolve the M01 prerequisite and complete the requested module.
    foreach ($module in 5, 6) {
        Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'NotStarted', StartedAtUtc=NULL, CompletedAtUtc=NULL, LastError=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber=$module;" | Out-Null
        $runD = Invoke-Runner -Modules @($module)
        if ($runD.ExitCode -ne 0) { Add-Failure "Independent run of M$('{0:d2}' -f $module) exited non-zero. Output: $($runD.Output)" }
        if ((Get-ModuleStatus -Module $module) -ne 'Completed') { Add-Failure "Independent run of M$('{0:d2}' -f $module) did not Complete." }
        if ((Get-ModuleStatus -Module 1) -ne 'Completed') { Add-Failure "Independent run of M$('{0:d2}' -f $module) must keep the M01 prerequisite Completed." }
    }
    Assert-Count 'security.SecureCustomers after independent M05' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM security.SecureCustomers;') 6
    Assert-Count 'ops.PerformanceOrders after independent M06' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') 10000

    # --- Canonical data must be unchanged (exercises roll back) --------------
    Assert-Count 'sales.Orders count (canonical intact)' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.Orders;') $ordersBefore
    Assert-Count 'sales.OrderItems count (canonical intact)' (Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM sales.OrderItems;') $orderItemsBefore
    if ((Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT OrderStatus FROM sales.Orders WHERE OrderID=3;') -ne $order3Before) { Add-Failure "Canonical sales.Orders row 3 status changed (expected '$order3Before')." }

    # --- Isolation: no database other than AdventureGearAI may change ---------
    $after = Get-DatabaseSet
    $beforeOthers = @($before | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $afterOthers = @($after | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $diff = Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers
    if ($diff) { Add-Failure "Databases other than AdventureGearAI changed: $(($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')" }
}
finally {
    # Restore the M01-M06 state rows exactly to the pre-test snapshot.
    try {
        foreach ($module in $modules) {
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

Write-Host 'PASS (focused M01-M06 runtime integration checks succeeded)' -ForegroundColor Green
exit 0
