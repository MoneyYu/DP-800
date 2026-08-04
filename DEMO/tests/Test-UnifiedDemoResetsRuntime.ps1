[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# ---------------------------------------------------------------------------
# Task 6 runtime integration for the module-scoped and full reset workflows,
# exercised against a local SQL Server 2025 (mssql2025) container using the real
# production reset scripts, the hybrid runner, and the core bootstrap:
#   * after all modules complete, each module reset removes ONLY its own objects
#     while unrelated module objects and the canonical core are retained;
#   * dependency/staleness reset (M01 -> M02..M11; M09 -> M10/M11; M10 -> M11);
#   * the runner can reapply a reset module and its dependents;
#   * the wrong-database guard blocks a reset against a non-AdventureGearAI target
#     (both the tooling guard and the reset's inline guard);
#   * the full reset drops and recreates AdventureGearAI, leaving a freshly
#     bootstrapped core (no module objects, all module state NotStarted), and is
#     safe to re-run;
#   * the set of databases other than AdventureGearAI is identical before/after.
# The password is taken from the container and never echoed. The suite ends with
# a full reset, so the database is returned to a clean freshly bootstrapped core
# and no database other than AdventureGearAI is touched.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$runnerScript = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$sqlRunnerScript = Join-Path $demoRoot 'scripts\Invoke-Dp800Sql.ps1'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$fullResetWrapper = Join-Path $demoRoot 'reset\Reset-AdventureGearAI.ps1'

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
function Get-Scalar { param([string]$Query) return (Invoke-Query -Database 'AdventureGearAI' -Query $Query | Select-Object -First 1) }
function Get-Int { param([string]$Query) return [int](Get-Scalar -Query $Query) }
function Get-ModuleStatus { param([int]$Module) return (Get-Scalar -Query "SET NOCOUNT ON; SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber=$Module;") }
function Test-ObjectPresent { param([string]$Object) return ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID('$Object') IS NOT NULL THEN 1 ELSE 0 END;") -eq 1) }
function Get-DatabaseSet {
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Invoke-Query -Database 'master' -Query 'SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name;'),
        [System.StringComparer]::OrdinalIgnoreCase)
}
function Invoke-Bootstrap { param([int[]]$Modules)
    $moduleArg = if ($Modules) { ($Modules -join ',') } else { '' }
    $command = "& '$bootstrapScript' -Server '$Server' -User '$User'"
    if ($moduleArg) { $command += " -Modules $moduleArg" }
    $out = & pwsh -NoProfile -Command $command 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}
function Invoke-Runner { param([int[]]$Modules, [switch]$Force)
    $command = "& '$runnerScript' -Server '$Server' -User '$User' -Modules $($Modules -join ',')"
    if ($Force) { $command += ' -Force' }
    $out = & pwsh -NoProfile -Command $command 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}
function Invoke-ModuleReset { param([int]$Module)
    $reset = Join-Path $demoRoot ("M{0:d2}\reset\reset.sql" -f $Module)
    $out = & pwsh -NoProfile -File $sqlRunnerScript -Server $Server -User $User -Database AdventureGearAI -InputFile $reset 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}
function Assert-Status { param([int]$Module, [string]$Expected)
    $s = Get-ModuleStatus -Module $Module
    if ($s -ne $Expected) { Add-Failure "M$('{0:d2}' -f $Module) status is '$s' (expected '$Expected')." }
}
function Assert-Present { param([string]$Object) if (-not (Test-ObjectPresent -Object $Object)) { Add-Failure "Expected object '$Object' to be present but it is missing." } }
function Assert-Absent { param([string]$Object) if (Test-ObjectPresent -Object $Object) { Add-Failure "Expected object '$Object' to be removed but it is still present." } }

# One representative object owned by each module (for teardown coverage).
$moduleSignature = @{
    1 = 'catalog.ProductPrice'; 2 = 'sales.OrderStatusAudit'; 3 = 'ops.EmployeeHierarchy'
    5 = 'security.SecureCustomers'; 6 = 'ops.PerformanceOrders'; 7 = 'ops.DeploymentLog'
    8 = 'api.Products'; 9 = 'ai.EmbeddingDocuments'; 10 = 'search.SearchDocuments'; 11 = 'ai.usp_BuildRagPrompt'
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
    if ((Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM ops.DemoEnvironment WHERE DemoEnvironmentID=1 AND DatabaseName=N'AdventureGearAI';") -ne 1) {
        Add-Failure "[$Context] ops.DemoEnvironment marker row is missing."
    }
}

Write-Host 'Task 6 runtime integration: scoped and full AdventureGearAI reset workflows'
Write-Host ''

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    # --- Phase 1: provision the full core + all modules ----------------------
    # Provision the core, then run all modules through the runner (which parses
    # an integer array correctly, unlike the bootstrap's -File module delegation).
    $coreProv = Invoke-Bootstrap
    if ($coreProv.ExitCode -ne 0) { throw "Core bootstrap failed. Output: $($coreProv.Output)" }
    $prov = Invoke-Runner -Modules @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    if ($prov.ExitCode -ne 0) { throw "Provisioning modules failed. Output: $($prov.Output)" }
    $before = Get-DatabaseSet
    foreach ($m in 1..11) { Assert-Status -Module $m -Expected 'Completed' }
    foreach ($m in $moduleSignature.Keys) { Assert-Present -Object $moduleSignature[$m] }
    Assert-CoreIntact -Context 'after provisioning'

    # M08 can leave its owned CDC capture active while M01 is force-reapplied.
    # M01 must safely coordinate that lifecycle before replacing its XTP table.
    $forceM01 = Invoke-Runner -Modules @(1) -Force
    if ($forceM01.ExitCode -ne 0) { Add-Failure "Forced M01 reapply with M08 CDC exited non-zero. Output: $($forceM01.Output)" }
    Assert-Present -Object 'catalog.ProductCacheInMemory'
    Assert-Status -Module 1 -Expected 'Completed'
    Assert-Status -Module 8 -Expected 'NotStarted'
    $reapply8 = Invoke-Runner -Modules @(8)
    if ($reapply8.ExitCode -ne 0) { Add-Failure "Reapply M08 after forced M01 reapply exited non-zero. Output: $($reapply8.Output)" }
    Assert-Status -Module 8 -Expected 'Completed'

    # --- Phase 2: M10 reset marks M11 stale; M09 stays Completed -------------
    $r10 = Invoke-ModuleReset -Module 10
    if ($r10.ExitCode -ne 0) { Add-Failure "M10 reset exited non-zero. Output: $($r10.Output)" }
    Assert-Absent -Object 'search.SearchDocuments'
    Assert-Present -Object 'ai.usp_BuildRagPrompt'   # M11 object not dropped by M10 reset
    Assert-Status -Module 10 -Expected 'NotStarted'
    Assert-Status -Module 11 -Expected 'NotStarted'
    Assert-Status -Module 9 -Expected 'Completed'
    Assert-Status -Module 8 -Expected 'Completed'
    Assert-CoreIntact -Context 'after M10 reset'
    # Reapply M10 (runner resolves 1,9 already Completed, runs 10).
    $reapply10 = Invoke-Runner -Modules @(10)
    if ($reapply10.ExitCode -ne 0) { Add-Failure "Reapply M10 exited non-zero. Output: $($reapply10.Output)" }
    Assert-Present -Object 'search.SearchDocuments'
    Assert-Status -Module 10 -Expected 'Completed'
    Assert-Status -Module 11 -Expected 'NotStarted'

    # --- Phase 3: M09 reset marks M10 and M11 stale -------------------------
    $bringBack11 = Invoke-Runner -Modules @(11)   # complete M11 so staleness is observable from Completed
    if ($bringBack11.ExitCode -ne 0) { Add-Failure "Completing M11 exited non-zero. Output: $($bringBack11.Output)" }
    Assert-Status -Module 11 -Expected 'Completed'
    $r9 = Invoke-ModuleReset -Module 9
    if ($r9.ExitCode -ne 0) { Add-Failure "M09 reset exited non-zero. Output: $($r9.Output)" }
    Assert-Absent -Object 'ai.EmbeddingDocuments'
    Assert-Present -Object 'search.SearchDocuments'   # M10 object not dropped by M09 reset
    Assert-Status -Module 9 -Expected 'NotStarted'
    Assert-Status -Module 10 -Expected 'NotStarted'
    Assert-Status -Module 11 -Expected 'NotStarted'
    Assert-Status -Module 8 -Expected 'Completed'
    Assert-CoreIntact -Context 'after M09 reset'
    # Reapply the whole AI chain.
    $reapply11 = Invoke-Runner -Modules @(11)
    if ($reapply11.ExitCode -ne 0) { Add-Failure "Reapply AI chain exited non-zero. Output: $($reapply11.Output)" }
    Assert-Present -Object 'ai.EmbeddingDocuments'
    foreach ($m in 9, 10, 11) { Assert-Status -Module $m -Expected 'Completed' }

    # --- Phase 4: M01 reset cascades staleness to M02..M11 ------------------
    $r1 = Invoke-ModuleReset -Module 1
    if ($r1.ExitCode -ne 0) { Add-Failure "M01 reset exited non-zero. Output: $($r1.Output)" }
    Assert-Absent -Object 'catalog.ProductPrice'
    Assert-Absent -Object 'sales.PartitionedOrders'
    Assert-Absent -Object 'catalog.ProductJsonTeaching'
    Assert-Absent -Object 'ops.InventoryLedger'
    Assert-Absent -Object 'catalog.ProductSkuSequenceDemo'
    Assert-Absent -Object 'catalog.ProductConstraintParent'
    if ((Get-Int "SET NOCOUNT ON; SELECT CONVERT(int, SERVERPROPERTY('IsXTPSupported'));") -eq 1) {
        Assert-Absent -Object 'catalog.ProductCacheInMemory'
    }
    if ((Get-Int "SET NOCOUNT ON; SELECT CONVERT(int, SERVERPROPERTY('IsPolyBaseInstalled'));") -eq 1) {
        Assert-Absent -Object 'catalog.ProductMetadataExternal'
    }
    if ((Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.json_indexes WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'IX_Products_ProductMetadata';") -ne 0) {
        Add-Failure 'M01 reset must drop the native JSON index IX_Products_ProductMetadata.'
    }
    if ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN COL_LENGTH('catalog.Products','MetadataFrame') IS NOT NULL THEN 1 ELSE 0 END;") -ne 0) { Add-Failure 'M01 reset must drop the catalog.Products.MetadataFrame computed column.' }
    foreach ($m in 2..11) { Assert-Status -Module $m -Expected 'NotStarted' }
    Assert-Status -Module 1 -Expected 'NotStarted'
    # Dependent objects are only marked stale, not physically dropped by M01 reset.
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') -ne 10000) { Add-Failure 'M01 reset must not drop the M06 workload (only mark it stale).' }
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM security.SecureCustomers;') -ne 120) { Add-Failure 'M01 reset must not drop the 120-row M05 companion table (only mark it stale).' }
    Assert-CoreIntact -Context 'after M01 reset'
    # Reapply M01 and representative dependents.
    $reapply1 = Invoke-Runner -Modules @(1)
    if ($reapply1.ExitCode -ne 0) { Add-Failure "Reapply M01 exited non-zero. Output: $($reapply1.Output)" }
    Assert-Present -Object 'catalog.ProductPrice'
    Assert-Present -Object 'catalog.ProductJsonTeaching'
    Assert-Present -Object 'ops.InventoryLedger'
    Assert-Present -Object 'catalog.ProductSkuSequenceDemo'
    Assert-Present -Object 'catalog.ProductConstraintParent'
    if ((Get-Int "SET NOCOUNT ON; SELECT CONVERT(int, SERVERPROPERTY('IsXTPSupported'));") -eq 1) {
        Assert-Present -Object 'catalog.ProductCacheInMemory'
    }
    if ((Get-Int "SET NOCOUNT ON; SELECT CONVERT(int, SERVERPROPERTY('IsPolyBaseInstalled'));") -eq 1) {
        Assert-Present -Object 'catalog.ProductMetadataExternal'
    }
    if ((Get-Int "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.json_indexes WHERE object_id = OBJECT_ID(N'catalog.Products') AND name = N'IX_Products_ProductMetadata';") -ne 1) {
        Add-Failure 'M01 reapply must recreate the native JSON index IX_Products_ProductMetadata.'
    }
    Assert-Status -Module 1 -Expected 'Completed'
    $reapply2 = Invoke-Runner -Modules @(2)
    if ($reapply2.ExitCode -ne 0) { Add-Failure "Reapply M02 exited non-zero. Output: $($reapply2.Output)" }
    Assert-Status -Module 2 -Expected 'Completed'
    $reapplyAi = Invoke-Runner -Modules @(11)
    if ($reapplyAi.ExitCode -ne 0) { Add-Failure "Reapply AI chain after cascade exited non-zero. Output: $($reapplyAi.Output)" }
    foreach ($m in 9, 10, 11) { Assert-Status -Module $m -Expected 'Completed' }

    # --- Phase 5: per-module teardown coverage (reverse order) --------------
    # Every module object is present now (M03..M08 were only marked stale, never
    # dropped, by the cascade; M01/M02/M09/M10/M11 were reapplied above).
    foreach ($m in $moduleSignature.Keys) { Assert-Present -Object $moduleSignature[$m] }
    $reverse = 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1
    for ($i = 0; $i -lt $reverse.Count; $i++) {
        $m = $reverse[$i]
        $r = Invoke-ModuleReset -Module $m
        if ($r.ExitCode -ne 0) { Add-Failure "Reverse teardown M$('{0:d2}' -f $m) reset exited non-zero. Output: $($r.Output)" }
        if ($moduleSignature.ContainsKey($m)) { Assert-Absent -Object $moduleSignature[$m] }
        # The next-to-be-reset module's object (if any) must still be present.
        for ($j = $i + 1; $j -lt $reverse.Count; $j++) {
            $n = $reverse[$j]
            if ($moduleSignature.ContainsKey($n)) { Assert-Present -Object $moduleSignature[$n]; break }
        }
        Assert-CoreIntact -Context "after reverse teardown M$('{0:d2}' -f $m)"
    }
    # After the full sweep every module object is gone but the core is intact.
    foreach ($m in $moduleSignature.Keys) { Assert-Absent -Object $moduleSignature[$m] }
    foreach ($m in 1..11) { Assert-Status -Module $m -Expected 'NotStarted' }
    Assert-CoreIntact -Context 'after complete reverse teardown'

    # --- Phase 6: wrong-database guard --------------------------------------
    # (a) Tooling guard (Invoke-Dp800Sql) blocks a non-AdventureGearAI target.
    $guardTooling = & pwsh -NoProfile -File $sqlRunnerScript -Server $Server -User $User -Database tempdb -InputFile (Join-Path $demoRoot 'M02\reset\reset.sql') 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Add-Failure "Tooling guard must block a module reset against tempdb. Output: $guardTooling" }
    if ($guardTooling -notmatch '(?i)guard failed') { Add-Failure "Tooling guard failure message was not explicit. Output: $guardTooling" }
    # (b) The reset's own inline guard aborts a direct run against the wrong DB.
    $inline = & $sqlcmd.Source -S $Server -U $User -d tempdb -i (Join-Path $demoRoot 'M02\reset\reset.sql') -b -r 1 -C 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Add-Failure "Inline reset guard must abort a direct run against tempdb. Output: $inline" }
    if ($inline -notmatch '(?i)reset guard failed') { Add-Failure "Inline reset guard message was not explicit. Output: $inline" }
    # tempdb must not have been mutated by the aborted reset.
    if ((& $sqlcmd.Source -S $Server -U $User -d tempdb -Q "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID('ops.DemoModuleState') IS NULL THEN 'clean' ELSE 'dirty' END;" -h -1 -W -C 2>&1 | Out-String) -notmatch 'clean') { Add-Failure 'Aborted reset must not create objects in tempdb.' }

    # --- Phase 7: full reset drops and recreates AdventureGearAI ------------
    # A sentinel proves the database was actually dropped and recreated.
    Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; IF OBJECT_ID('ops.FullResetSentinel','U') IS NULL CREATE TABLE ops.FullResetSentinel (Id int);" | Out-Null
    Assert-Present -Object 'ops.FullResetSentinel'
    $full = & pwsh -NoProfile -File $fullResetWrapper -Server $Server -User $User 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "Full reset wrapper exited non-zero. Output: $full" }
    if (-not (Get-DatabaseSet).Contains('AdventureGearAI')) { Add-Failure 'Full reset must leave AdventureGearAI existing (freshly bootstrapped).' }
    Assert-Absent -Object 'ops.FullResetSentinel'   # proves the DB was dropped and recreated
    Assert-CoreIntact -Context 'after full reset'
    Assert-Absent -Object 'catalog.ProductPrice'    # no module objects after a fresh bootstrap
    Assert-Absent -Object 'ops.PerformanceOrders'
    foreach ($m in 1..11) { Assert-Status -Module $m -Expected 'NotStarted' }
    # Re-running the full reset is safe and deterministic.
    $fullAgain = & pwsh -NoProfile -File $fullResetWrapper -Server $Server -User $User 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "Re-running the full reset wrapper exited non-zero. Output: $fullAgain" }
    Assert-CoreIntact -Context 'after full reset rerun'

    # --- Phase 8: isolation - no database other than AdventureGearAI changed --
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

Write-Host 'PASS (Task 6 runtime reset workflow checks succeeded)' -ForegroundColor Green
exit 0
