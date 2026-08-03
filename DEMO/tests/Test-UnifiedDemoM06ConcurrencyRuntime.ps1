[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# ---------------------------------------------------------------------------
# Item 8 runtime validation of the M06 concurrency demos against a local SQL
# Server 2025 (mssql2025) container, driving the REAL production interactive
# scripts across concurrent sqlcmd sessions:
#
#   * Blocking (three sessions): 02-blocker.sql holds a lock, 03-blocked.sql
#     waits behind it, and 04-observe-blocking.sql (a third session) observes the
#     blocked/blocking relationship. The blocked statement must be the M06
#     ops.PerformanceOrders update, and once the blocker rolls back the blocked
#     session completes and NO open transaction is left behind.
#   * Deadlock: 05-deadlock-session-a.sql and 06-deadlock-session-b.sql acquire
#     locks in the opposite order; SQL Server resolves the deadlock (error 1205)
#     and the low-priority session A is chosen as the victim while session B
#     commits. No open transaction is left behind.
#
# M06 is provisioned through the production runner (which resolves the M01
# prerequisite). The suite ends with a full reset, so AdventureGearAI is returned
# to a clean freshly bootstrapped core and no other database is touched. The SA
# password is read from the container and never echoed.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$runnerScript = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$fullResetWrapper = Join-Path $demoRoot 'reset\Reset-AdventureGearAI.ps1'
$m06 = Join-Path $demoRoot 'M06\local'

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

$sqlcmdPath = $sqlcmd.Source

function Invoke-Query {
    param([string]$Database, [string]$Query)
    $result = & $sqlcmdPath -S $Server -U $User -d $Database -Q $Query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed against '$Database': $($result -join ' ')" }
    return @($result | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
}
function Get-Scalar { param([string]$Query) return (Invoke-Query -Database 'AdventureGearAI' -Query $Query | Select-Object -First 1) }
function Get-Int { param([string]$Query) return [int](Get-Scalar -Query $Query) }
function Get-DatabaseSet {
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Invoke-Query -Database 'master' -Query 'SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name;'),
        [System.StringComparer]::OrdinalIgnoreCase)
}

# Number of open transactions currently held by any session connected to
# AdventureGearAI (used to prove the concurrency demos leave nothing behind).
function Get-OpenTransactionCount {
    return [int]((Invoke-Query -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT COUNT(*)
FROM sys.dm_tran_session_transactions AS t
INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = t.session_id
WHERE DB_NAME(s.database_id) = N'AdventureGearAI';
"@) | Select-Object -First 1)
}
function Get-BlockedRequestCount {
    return [int]((Invoke-Query -Database 'master' -Query @"
SET NOCOUNT ON;
SELECT COUNT(*)
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.blocking_session_id <> 0 AND DB_NAME(s.database_id) = N'AdventureGearAI';
"@) | Select-Object -First 1)
}

# Launch a production .sql script as an independent background sqlcmd session.
# Start-Job spawns a child process that inherits SQLCMDPASSWORD from this process.
function Start-SqlSession {
    param([string]$ScriptFile)
    return Start-Job -ScriptBlock {
        param($sqlcmdPath, $Server, $User, $ScriptFile)
        & $sqlcmdPath -S $Server -U $User -C -d 'AdventureGearAI' -i $ScriptFile 2>&1 | Out-String
    } -ArgumentList $sqlcmdPath, $Server, $User, $ScriptFile
}

Write-Host 'M06 concurrency runtime validation (blocking + deadlock via sqlcmd sessions)'
Write-Host ''

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
$activeJobs = [System.Collections.Generic.List[object]]::new()

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    $before = Get-DatabaseSet

    # --- Provision core + M06 through the production runner -------------------
    Write-Host '--- Provisioning core + M06 (production runner) ---'
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $prov = & pwsh -NoProfile -Command "& '$runnerScript' -Server '$Server' -User '$User' -Modules 6 -Force" 2>&1 | Out-String
    $provCode = $LASTEXITCODE
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    if ($provCode -ne 0) { throw "Provisioning M06 failed. Output: $prov" }
    if ((Get-Int 'SET NOCOUNT ON; SELECT COUNT(*) FROM ops.PerformanceOrders;') -ne 10000) { Add-Failure 'M06 workload ops.PerformanceOrders was not provisioned with 10000 rows.' }
    if ((Get-OpenTransactionCount) -ne 0) { Add-Failure 'Precondition: an open transaction already exists against AdventureGearAI before the blocking demo.' }

    # --- Scenario A: blocking across three sessions --------------------------
    Write-Host '--- Scenario A: blocking (blocker + blocked + observer) ---'
    $blockerJob = Start-SqlSession -ScriptFile (Join-Path $m06 '02-blocker.sql')
    $activeJobs.Add($blockerJob)
    Start-Sleep -Seconds 1
    $blockedJob = Start-SqlSession -ScriptFile (Join-Path $m06 '03-blocked.sql')
    $activeJobs.Add($blockedJob)

    # Deterministically wait for the blocked/blocking relationship to form.
    $blockingObserved = $false
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        if ((Get-BlockedRequestCount) -ge 1) { $blockingObserved = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $blockingObserved) { Add-Failure 'Blocking relationship never formed between the blocker and blocked sessions.' }

    if ($blockingObserved) {
        # Third session: the production observer script must report the pair.
        $observer = & $sqlcmdPath -S $Server -U $User -C -d 'AdventureGearAI' -i (Join-Path $m06 '04-observe-blocking.sql') -b 2>&1 | Out-String
        if ($observer -notmatch 'PerformanceOrders') { Add-Failure "Observer did not report the blocked ops.PerformanceOrders statement. Output: $observer" }
        if ($observer -notmatch '(?i)LCK_') { Add-Failure "Observer did not report a lock wait for the blocked session. Output: $observer" }
    }

    # Let the blocker roll back (WAITFOR 20s) and the blocked statement finish.
    $null = Wait-Job -Job $blockerJob, $blockedJob -Timeout 40
    $blockerOut = (Receive-Job -Job $blockerJob) -join ' '
    $blockedOut = (Receive-Job -Job $blockedJob) -join ' '
    if ($blockerJob.State -ne 'Completed') { Add-Failure "Blocker session did not complete (state=$($blockerJob.State))." }
    if ($blockedJob.State -ne 'Completed') { Add-Failure "Blocked session did not complete (state=$($blockedJob.State))." }
    if ($blockedOut -notmatch '1 rows affected') { Add-Failure "Blocked session did not apply its update after the blocker released. Output: $blockedOut" }

    # Cleanup assertions: no open transactions and no blocked requests remain.
    if ((Get-BlockedRequestCount) -ne 0) { Add-Failure 'A blocked request is still present after the blocking demo completed.' }
    if ((Get-OpenTransactionCount) -ne 0) { Add-Failure 'An open transaction against AdventureGearAI remains after the blocking demo.' }

    # --- Scenario B: deadlock -----------------------------------------------
    Write-Host '--- Scenario B: deadlock (session A low-priority victim) ---'
    $sessionA = Start-SqlSession -ScriptFile (Join-Path $m06 '05-deadlock-session-a.sql')
    $activeJobs.Add($sessionA)
    $sessionB = Start-SqlSession -ScriptFile (Join-Path $m06 '06-deadlock-session-b.sql')
    $activeJobs.Add($sessionB)
    $null = Wait-Job -Job $sessionA, $sessionB -Timeout 60
    $outA = (Receive-Job -Job $sessionA) -join "`n"
    $outB = (Receive-Job -Job $sessionB) -join "`n"
    if ($sessionA.State -ne 'Completed') { Add-Failure "Deadlock session A did not complete (state=$($sessionA.State))." }
    if ($sessionB.State -ne 'Completed') { Add-Failure "Deadlock session B did not complete (state=$($sessionB.State))." }
    if (($outA + $outB) -notmatch '1205') { Add-Failure "No deadlock (error 1205) was raised. A: $outA B: $outB" }
    if ($outA -notmatch '1205') { Add-Failure "The low-priority session A was expected to be the deadlock victim (1205). A: $outA" }
    if ($outB -match '1205') { Add-Failure "Session B should have survived the deadlock but reported 1205. B: $outB" }

    if ((Get-OpenTransactionCount) -ne 0) { Add-Failure 'An open transaction against AdventureGearAI remains after the deadlock demo.' }

    # --- Cleanup: full reset to a clean core; verify isolation --------------
    Write-Host '--- Full reset to a clean core ---'
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $null, 'Process')
    $reset = & pwsh -NoProfile -File $fullResetWrapper -Server $Server -User $User 2>&1 | Out-String
    $resetCode = $LASTEXITCODE
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    if ($resetCode -ne 0) { Add-Failure "Final full reset failed. Output: $reset" }
    if ((Get-Int "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID('ops.PerformanceOrders') IS NULL THEN 0 ELSE 1 END;") -ne 0) { Add-Failure 'Full reset did not remove the M06 workload table.' }

    $after = Get-DatabaseSet
    $beforeOthers = @($before | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $afterOthers = @($after | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $diff = Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers
    if ($diff) { Add-Failure "Databases other than AdventureGearAI changed: $(($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')" }
}
finally {
    foreach ($job in $activeJobs) {
        try {
            if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
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

Write-Host 'PASS (M06 blocking and deadlock concurrency checks succeeded)' -ForegroundColor Green
exit 0
