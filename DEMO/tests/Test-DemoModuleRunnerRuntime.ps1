[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$scriptsRoot = Join-Path $demoRoot 'scripts'
$runnerScript = Join-Path $scriptsRoot 'Invoke-DemoModule.ps1'
$sqlRunnerScript = Join-Path $scriptsRoot 'Invoke-Dp800Sql.ps1'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$sandboxRoot = Join-Path $PSScriptRoot '.runner-runtime-sandbox'

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
function Get-ProbeCount {
    return [int](Get-Scalar -Database 'AdventureGearAI' -Query 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.DemoRunnerProbe;')
}

Write-Host 'Dependency-aware module runner runtime integration test'
Write-Host ''

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
$testedModules = @(1, 9, 10, 11)
$stateSnapshot = @{}

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

    # 1) Ensure the AdventureGearAI core exists (also snapshots the databases set).
    $before = Get-DatabaseSet
    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Core bootstrap failed during test setup.' }

    # Snapshot the tested module rows so we can restore them exactly afterward.
    foreach ($module in $testedModules) {
        $row = Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(
    Status, '~',
    ISNULL(CONVERT(nvarchar(30), StartedAtUtc, 126), ''), '~',
    ISNULL(CONVERT(nvarchar(30), CompletedAtUtc, 126), ''), '~',
    ISNULL(REPLACE(LastError, '~', ' '), ''))
FROM ops.DemoModuleState WHERE ModuleNumber=$module;
"@
        $stateSnapshot[$module] = $row
    }

    # Create a scratch probe table (owned only by this test) to count executions.
    Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; IF OBJECT_ID(N'ops.DemoRunnerProbe', N'U') IS NOT NULL DROP TABLE ops.DemoRunnerProbe; CREATE TABLE ops.DemoRunnerProbe (Id int IDENTITY(1,1) PRIMARY KEY, RanAtUtc datetime2(3) NOT NULL CONSTRAINT DF_DemoRunnerProbe DEFAULT SYSUTCDATETIME());" | Out-Null

    # Reset tested module state to a known NotStarted baseline for the scenario.
    Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'NotStarted', StartedAtUtc=NULL, CompletedAtUtc=NULL, LastError=NULL, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber IN (1,9,10,11);" | Out-Null

    # Safe dummy setup scripts (do NOT modify production module scripts).
    $goodSql = Join-Path $sandboxRoot 'good-setup.sql'
    $badSql = Join-Path $sandboxRoot 'bad-setup.sql'
    Set-Content -LiteralPath $goodSql -Value "SET NOCOUNT ON;`r`nINSERT ops.DemoRunnerProbe DEFAULT VALUES;`r`nPRINT N'dummy setup ok';" -NoNewline
    Set-Content -LiteralPath $badSql -Value "SET NOCOUNT ON;`r`nRAISERROR(N'intentional dummy failure for runner test', 16, 1);" -NoNewline

    function New-Manifest {
        param([string]$Name, [hashtable]$ModuleToScript)
        $modules = foreach ($m in ($ModuleToScript.Keys | Sort-Object)) {
            @{ module = [int]$m; ready = $true; setup = @{ common = @($ModuleToScript[$m]); local = @(); azure = @() } }
        }
        $path = Join-Path $sandboxRoot $Name
        Set-Content -LiteralPath $path -Value (@{ schemaVersion = '1.0.0'; modules = @($modules) } | ConvertTo-Json -Depth 6) -NoNewline
        return $path
    }

    $goodManifest = New-Manifest -Name 'good-manifest.json' -ModuleToScript @{ 1 = 'good-setup.sql'; 9 = 'good-setup.sql'; 10 = 'good-setup.sql'; 11 = 'good-setup.sql' }
    $failManifest = New-Manifest -Name 'fail-manifest.json' -ModuleToScript @{ 1 = 'good-setup.sql'; 9 = 'good-setup.sql'; 10 = 'bad-setup.sql'; 11 = 'good-setup.sql' }

    # --- Scenario A: first run of M11 resolves M01/M09/M10/M11 and Completes ---
    $runOutput = & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 11 -ManifestPath $goodManifest 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "First runner run (M11) exited non-zero. Output: $runOutput" }
    if ($runOutput -notmatch 'M01, M09, M10, M11') { Add-Failure "Runner did not report the resolved plan M01,M09,M10,M11. Output: $runOutput" }
    foreach ($module in 1, 9, 10, 11) {
        $status = Get-ModuleStatus -Module $module
        if ($status -ne 'Completed') { Add-Failure "After first run, M$('{0:d2}' -f $module) status is '$status' (expected Completed)." }
    }
    $countAfterFirst = Get-ProbeCount
    if ($countAfterFirst -ne 4) { Add-Failure "First run should execute 4 setup scripts; probe count is $countAfterFirst (expected 4)." }

    # --- Scenario B: rerun without -Force skips all Completed modules ----------
    $rerunOutput = & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 11 -ManifestPath $goodManifest 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "Rerun (M11) exited non-zero. Output: $rerunOutput" }
    if ($rerunOutput -notmatch 'already Completed; skipping') { Add-Failure "Rerun should skip Completed modules. Output: $rerunOutput" }
    $countAfterRerun = Get-ProbeCount
    if ($countAfterRerun -ne 4) { Add-Failure "Rerun should skip (no new executions); probe count is $countAfterRerun (expected 4)." }

    # --- Scenario C: -Force re-runs all resolved modules ----------------------
    $forceOutput = & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 11 -Force -ManifestPath $goodManifest 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "Force rerun (M11) exited non-zero. Output: $forceOutput" }
    foreach ($module in 1, 9, 10, 11) {
        $status = Get-ModuleStatus -Module $module
        if ($status -ne 'Completed') { Add-Failure "After -Force, M$('{0:d2}' -f $module) status is '$status' (expected Completed)." }
    }
    $countAfterForce = Get-ProbeCount
    if ($countAfterForce -ne 8) { Add-Failure "Force should re-execute 4 setup scripts; probe count is $countAfterForce (expected 8)." }

    # --- Scenario D: a failing setup marks the module Failed and rethrows -----
    Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'NotStarted', StartedAtUtc=NULL, CompletedAtUtc=NULL, LastError=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber IN (1,9,10,11);" | Out-Null
    $failOutput = & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 11 -ManifestPath $failManifest 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Add-Failure "Runner must exit non-zero when a module setup fails. Output: $failOutput" }
    $m10Status = Get-ModuleStatus -Module 10
    if ($m10Status -ne 'Failed') { Add-Failure "M10 status after failure is '$m10Status' (expected Failed)." }
    $m10Error = Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT LastError FROM ops.DemoModuleState WHERE ModuleNumber=10;"
    if ([string]::IsNullOrWhiteSpace($m10Error)) { Add-Failure 'M10 LastError must be recorded on failure.' }
    $m11Status = Get-ModuleStatus -Module 11
    if ($m11Status -eq 'Completed') { Add-Failure 'M11 must NOT be Completed when its M10 prerequisite failed (runner must rethrow before M11).' }
    # M01/M09 precede M10 and should have Completed before the failure.
    foreach ($module in 1, 9) {
        $status = Get-ModuleStatus -Module $module
        if ($status -ne 'Completed') { Add-Failure "M$('{0:d2}' -f $module) should be Completed before the M10 failure; got '$status'." }
    }

    # --- Scenario E: wrong-database guard blocks execution --------------------
    $guardOutput = & pwsh -NoProfile -File $sqlRunnerScript -Server $Server -User $User -Database tempdb -InputFile $goodSql 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Add-Failure "Database guard must block a non-AdventureGearAI target. Output: $guardOutput" }
    if ($guardOutput -notmatch 'guard failed|Database guard failed') { Add-Failure "Guard failure message was not explicit. Output: $guardOutput" }

    # --- Isolation: only AdventureGearAI may differ; no other DB touched ------
    $after = Get-DatabaseSet
    $beforeOthers = @($before | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $afterOthers = @($after | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $diff = Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers
    if ($diff) { Add-Failure "Databases other than AdventureGearAI changed: $(( $diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')" }
}
finally {
    # Restore module state exactly and drop the scratch probe table.
    try {
        foreach ($module in $testedModules) {
            if (-not $stateSnapshot.ContainsKey($module)) { continue }
            $parts = "$($stateSnapshot[$module])".Split('~')
            $status = $parts[0]
            $started = if ($parts.Count -gt 1 -and $parts[1]) { "'" + $parts[1] + "'" } else { 'NULL' }
            $completed = if ($parts.Count -gt 2 -and $parts[2]) { "'" + $parts[2] + "'" } else { 'NULL' }
            $lastError = if ($parts.Count -gt 3 -and $parts[3]) { "N'" + ($parts[3] -replace "'", "''") + "'" } else { 'NULL' }
            Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET Status=N'$status', StartedAtUtc=$started, CompletedAtUtc=$completed, LastError=$lastError, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME() WHERE ModuleNumber=$module;" | Out-Null
        }
        Invoke-Query -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; IF OBJECT_ID(N'ops.DemoRunnerProbe', N'U') IS NOT NULL DROP TABLE ops.DemoRunnerProbe;" | Out-Null
    }
    catch { Write-Warning "Cleanup/restore encountered an issue: $($_.Exception.Message)" }

    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
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

Write-Host 'PASS (runtime module runner integration checks succeeded)' -ForegroundColor Green
exit 0
