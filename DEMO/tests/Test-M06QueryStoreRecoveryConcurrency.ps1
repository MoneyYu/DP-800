[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$planForcingPath = Join-Path $repoRoot 'DEMO\M06\local\08-query-store-plan-forcing.sql'
$resetPath = Join-Path $repoRoot 'DEMO\M06\reset\reset.sql'
$runnerPath = Join-Path $repoRoot 'DEMO\scripts\Invoke-DemoModule.ps1'
$workloadPath = Join-Path $repoRoot 'DEMO\M06\common\01-workload.sql'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Add-Failure $Message }
}

function Get-SourceIndex {
    param([string]$Text, [string]$Value, [switch]$Last)
    if ($Last) {
        return $Text.LastIndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return $Text.IndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase)
}

$planForcing = Get-Content -LiteralPath $planForcingPath -Raw
$reset = Get-Content -LiteralPath $resetPath -Raw
$resource = "N'DP800.M06.QueryStoreRecovery'"

foreach ($script in @(
    @{ Name = 'M06 plan forcing demo'; Text = $planForcing },
    @{ Name = 'M06 reset'; Text = $reset }
)) {
    Assert-True ($script.Text -match '(?i)sp_getapplock') "$($script.Name) must acquire the Query Store recovery application lock."
    Assert-True ($script.Text -match [regex]::Escape($resource)) "$($script.Name) must use the DP800.M06.QueryStoreRecovery application-lock resource."
    Assert-True ($script.Text -match '(?is)BEGIN\s+CATCH.*?sp_releaseapplock.*?THROW') "$($script.Name) must release the held application lock in CATCH before rethrowing."
}

$planLock = Get-SourceIndex $planForcing 'sp_getapplock'
$planWorkloadPrecondition = Get-SourceIndex $planForcing "IF OBJECT_ID(N'ops.PerformanceOrders', N'U') IS NULL"
$planQueryStoreWork = Get-SourceIndex $planForcing "IF OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NULL"
$planMigration = Get-SourceIndex $planForcing "IF COL_LENGTH(N'ops.M06QueryStoreRuntimeState'"
$planActiveRecoveryRead = Get-SourceIndex $planForcing "AND RecoveryPhase = N''Active''"
$planInitialStateDelete = Get-SourceIndex $planForcing 'DELETE FROM ops.M06QueryStoreRuntimeState'
$planFinalRelease = Get-SourceIndex $planForcing 'sp_releaseapplock' -Last
$planFinalCleanup = Get-SourceIndex $planForcing 'DELETE FROM ops.M06QueryStoreRuntimeState' -Last
Assert-True ($planLock -ge 0 -and $planMigration -gt $planLock) 'M06 plan forcing must lock before recovery-state schema migration.'
Assert-True ($planWorkloadPrecondition -gt $planLock -and $planWorkloadPrecondition -lt $planQueryStoreWork) 'M06 plan forcing must validate the workload only after acquiring the lifecycle lock and before Query Store work.'
Assert-True ($planFinalRelease -gt $planFinalCleanup) 'M06 plan forcing must retain the lock through recovery-state cleanup.'
Assert-True ($planForcing -match '(?is)SELECT\s+@currentQueryCaptureMode\s*=\s*query_capture_mode_desc.*?IF\s+@currentQueryCaptureMode\s*=\s*@expectedDemoQueryCaptureMode.*?ALTER\s+DATABASE\s+CURRENT\s+SET\s+QUERY_STORE') 'M06 plan forcing must reread the capture mode and restore only when it still matches the expected demo mode.'
Assert-True ($planActiveRecoveryRead -gt $planMigration -and $planActiveRecoveryRead -lt $planInitialStateDelete) 'M06 plan forcing must resolve an active interrupted recovery record before replacing it.'

$resetLock = Get-SourceIndex $reset 'sp_getapplock'
$resetMigration = Get-SourceIndex $reset "IF COL_LENGTH(N'ops.M06QueryStoreRuntimeState'"
$resetFinalRelease = Get-SourceIndex $reset 'sp_releaseapplock' -Last
$resetDrop = Get-SourceIndex $reset 'DROP TABLE IF EXISTS ops.M06QueryStoreRuntimeState'
Assert-True ($resetLock -ge 0 -and $resetMigration -gt $resetLock) 'M06 reset must lock before recovery-state schema migration.'
Assert-True ($resetFinalRelease -gt $resetDrop) 'M06 reset must retain the lock through recovery-state removal.'

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) source issue(s))" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $sqlcmd -or -not $docker) {
    Write-Host 'SKIP: sqlcmd or docker is not available.' -ForegroundColor Yellow
    exit 0
}

$running = (& $docker.Source ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
if (-not $running) {
    Write-Host "SKIP: container '$Container' is not running." -ForegroundColor Yellow
    exit 0
}

$password = (& $docker.Source exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Host "SKIP: MSSQL_SA_PASSWORD is not set in '$Container'." -ForegroundColor Yellow
    exit 0
}

function Invoke-Query {
    param([string]$Query)
    $output = & $sqlcmd.Source -S $Server -U $User -d AdventureGearAI -Q $Query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed: $($output -join ' ')" }
    return @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
}

function Invoke-SqlFile {
    param([string]$Path)
    $output = & $sqlcmd.Source -S $Server -U $User -d AdventureGearAI -i $Path -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd file '$Path' failed: $($output -join ' ')" }
}

function Start-SqlFile {
    param([string]$Path)
    Start-Job -ScriptBlock {
        param($SqlcmdPath, $TargetServer, $TargetUser, $SqlPath, $SqlPassword)
        $env:SQLCMDPASSWORD = $SqlPassword
        $output = & $SqlcmdPath -S $TargetServer -U $TargetUser -d AdventureGearAI -i $SqlPath -h -1 -W -b -C -I -x 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    } -ArgumentList $sqlcmd.Source, $Server, $User, $Path, $password
}

function Start-SqlQuery {
    param([string]$Query)
    Start-Job -ScriptBlock {
        param($SqlcmdPath, $TargetServer, $TargetUser, $SqlQuery, $SqlPassword)
        $env:SQLCMDPASSWORD = $SqlPassword
        $output = & $SqlcmdPath -S $TargetServer -U $TargetUser -d AdventureGearAI -Q $SqlQuery -h -1 -W -b -C -I -x 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    } -ArgumentList $sqlcmd.Source, $Server, $User, $Query, $password
}

function Wait-ForAppLockWait {
    param([int]$ExpectedCount, [string]$Label)
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $waitCount = [int](Invoke-Query @"
SELECT COUNT(*)
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.database_id = DB_ID(N'AdventureGearAI')
  AND r.wait_type LIKE N'LCK_M%'
  AND t.text = N'xp_userlock';
"@ | Select-Object -First 1)
        if ($waitCount -ge $ExpectedCount) { return }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)

    throw "$Label did not reach $ExpectedCount queued application-lock request(s)."
}

function Assert-ConcurrentSqlFiles {
    param([string]$Path, [string]$Label)
    $jobs = @(
        (Start-SqlFile -Path $Path)
        (Start-SqlFile -Path $Path)
    )
    try {
        $null = Wait-Job -Job $jobs -Timeout 180
        foreach ($job in $jobs) {
            if ($job.State -ne 'Completed') {
                Add-Failure "$Label did not complete (state=$($job.State))."
                continue
            }

            $result = Receive-Job -Job $job
            if ($result.ExitCode -ne 0) {
                Add-Failure "$Label failed concurrently: $($result.Output)"
            }
        }
    }
    finally {
        $jobs | ForEach-Object {
            if ($_.State -eq 'Running') { Stop-Job -Job $_ -ErrorAction SilentlyContinue }
            Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
        }
    }
}

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    $provision = & pwsh -NoProfile -File $runnerPath -Server $Server -User $User -Modules 6 -Force 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "M06 provisioning failed: $provision" }

    Invoke-Query @"
DROP TABLE IF EXISTS ops.M06QueryStoreRuntimeState;
CREATE TABLE ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID tinyint NOT NULL
        CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
        CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
    PriorQueryCaptureMode nvarchar(60) NOT NULL,
    RecordedAtUtc datetime2(0) NOT NULL
);
"@ | Out-Null
    Assert-ConcurrentSqlFiles -Path $planForcingPath -Label 'Two M06 plan-forcing calls against legacy recovery schema'

    Invoke-SqlFile -Path $resetPath
    Invoke-Query @"
CREATE TABLE ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID tinyint NOT NULL
        CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
        CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
    PriorQueryCaptureMode nvarchar(60) NOT NULL,
    RecordedAtUtc datetime2(0) NOT NULL
);
INSERT ops.M06QueryStoreRuntimeState
    (M06QueryStoreRuntimeStateID, PriorQueryCaptureMode, RecordedAtUtc)
VALUES (1, N'AUTO', SYSUTCDATETIME());
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
"@ | Out-Null
    Assert-ConcurrentSqlFiles -Path $resetPath -Label 'Two M06 reset calls against legacy recovery schema'

    Invoke-Query @"
CREATE TABLE ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID tinyint NOT NULL
        CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
        CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
    PriorQueryCaptureMode nvarchar(60) NOT NULL,
    ExpectedDemoQueryCaptureMode nvarchar(60) NOT NULL,
    RecoveryPhase nvarchar(30) NOT NULL,
    RecordedAtUtc datetime2(0) NOT NULL
);
INSERT ops.M06QueryStoreRuntimeState
    (M06QueryStoreRuntimeStateID, PriorQueryCaptureMode, ExpectedDemoQueryCaptureMode, RecoveryPhase, RecordedAtUtc)
VALUES (1, N'AUTO', N'ALL', N'Active', SYSUTCDATETIME());
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = NONE);
"@ | Out-Null
    Invoke-SqlFile -Path $resetPath
    $captureMode = Invoke-Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;'
    $stateExists = Invoke-Query "SELECT CASE WHEN OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NULL THEN N'0' ELSE N'1' END;"
    Assert-True ($captureMode[0] -eq 'NONE') 'M06 reset must not overwrite a stale manually selected Query Store capture mode.'
    Assert-True ($stateExists[0] -eq '0') 'M06 reset must clear stale recovery metadata after preserving the manual mode.'

    # Queue reset before the interactive plan-forcing demo behind a synchronized
    # lifecycle-lock holder. Once released, reset must remove the workload first;
    # the demo must then fail only with its intentional workload precondition.
    $provision = & pwsh -NoProfile -File $runnerPath -Server $Server -User $User -Modules 6 -Force 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "M06 reprovisioning failed: $provision" }

    Invoke-Query @"
CREATE TABLE ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID tinyint NOT NULL
        CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
        CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
    PriorQueryCaptureMode nvarchar(60) NOT NULL,
    ExpectedDemoQueryCaptureMode nvarchar(60) NOT NULL,
    RecoveryPhase nvarchar(30) NOT NULL
        CONSTRAINT CK_M06QueryStoreRuntimeState_RecoveryPhase
            CHECK (RecoveryPhase IN (N'Active', N'Restored')),
    RecordedAtUtc datetime2(0) NOT NULL
);
INSERT ops.M06QueryStoreRuntimeState
    (M06QueryStoreRuntimeStateID, PriorQueryCaptureMode, ExpectedDemoQueryCaptureMode, RecoveryPhase, RecordedAtUtc)
VALUES (1, N'AUTO', N'ALL', N'Active', SYSUTCDATETIME());
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
"@ | Out-Null
    Invoke-SqlFile -Path $planForcingPath
    $captureMode = Invoke-Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;'
    $stateCount = Invoke-Query 'SELECT COUNT(*) FROM ops.M06QueryStoreRuntimeState;'
    Assert-True ($captureMode[0] -eq 'AUTO') 'Rerunning M06 plan-forcing after an interrupted AUTO-to-ALL demo must restore AUTO.'
    Assert-True ($stateCount[0] -eq '0') 'Rerunning M06 plan-forcing after an interrupted demo must not leave a stale recovery record.'

    Invoke-Query @"
DROP TABLE IF EXISTS ops.M06QueryStoreRaceSync;
CREATE TABLE ops.M06QueryStoreRaceSync
(
    Actor nvarchar(30) NOT NULL CONSTRAINT PK_M06QueryStoreRaceSync PRIMARY KEY
);
"@ | Out-Null

    $blocker = Start-SqlQuery @"
DECLARE @lockResult int;
DECLARE @release bit = 0;
EXEC @lockResult = sys.sp_getapplock
    @Resource = N'DP800.M06.QueryStoreRecovery',
    @LockMode = N'Exclusive',
    @LockOwner = N'Session',
    @LockTimeout = 60000;
IF @lockResult < 0 THROW 51008, N'M06 regression blocker could not acquire the lifecycle lock.', 1;
INSERT ops.M06QueryStoreRaceSync (Actor) VALUES (N'Blocker');
WHILE @release = 0
BEGIN
    SET @release = CASE WHEN EXISTS (SELECT 1 FROM ops.M06QueryStoreRaceSync WHERE Actor = N'Release') THEN 1 ELSE 0 END;
    IF @release = 0 WAITFOR DELAY '00:00:00.100';
END;
EXEC sys.sp_releaseapplock
    @Resource = N'DP800.M06.QueryStoreRecovery',
    @LockOwner = N'Session';
"@
    $resetJob = $null
    $planJob = $null
    try {
        $blockerDeadline = (Get-Date).AddSeconds(30)
        do {
            $blockerReady = Invoke-Query "SELECT COUNT(*) FROM ops.M06QueryStoreRaceSync WHERE Actor = N'Blocker';"
            if ($blockerReady[0] -eq '1') { break }
            Start-Sleep -Milliseconds 100
        } while ((Get-Date) -lt $blockerDeadline)
        if ($blockerReady[0] -ne '1') { throw 'M06 regression blocker did not signal that it holds the lifecycle lock.' }

        $resetJob = Start-SqlFile -Path $resetPath
        Wait-ForAppLockWait -ExpectedCount 1 -Label 'M06 reset'
        $planJob = Start-SqlFile -Path $planForcingPath
        Wait-ForAppLockWait -ExpectedCount 2 -Label 'M06 plan-forcing and reset race'

        Invoke-Query "INSERT ops.M06QueryStoreRaceSync (Actor) VALUES (N'Release');" | Out-Null
        $null = Wait-Job -Job $blocker, $resetJob, $planJob -Timeout 90
        $blockerResult = Receive-Job -Job $blocker
        $resetResult = Receive-Job -Job $resetJob
        $planResult = Receive-Job -Job $planJob

        Assert-True ($blocker.State -eq 'Completed' -and $blockerResult.ExitCode -eq 0) "M06 regression blocker did not complete: $($blockerResult.Output)"
        Assert-True ($resetJob.State -eq 'Completed' -and $resetResult.ExitCode -eq 0) "M06 reset did not complete during the lifecycle race: $($resetResult.Output)"
        Assert-True ($planJob.State -eq 'Completed' -and $planResult.ExitCode -ne 0) "M06 plan-forcing must exit after reset removes its workload: $($planResult.Output)"
        Assert-True ($planResult.Output -match 'Run M06 common/01-workload\.sql before the plan-forcing demo') "M06 plan-forcing must report its controlled missing-workload error, not an object-race failure: $($planResult.Output)"

        $workloadExists = Invoke-Query "SELECT CASE WHEN OBJECT_ID(N'ops.PerformanceOrders', N'U') IS NULL THEN N'0' ELSE N'1' END;"
        $raceStateExists = Invoke-Query "SELECT CASE WHEN OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NULL THEN N'0' ELSE N'1' END;"
        Assert-True ($workloadExists[0] -eq '0') 'M06 reset must complete before the queued plan-forcing demo.'
        Assert-True ($raceStateExists[0] -eq '0') 'The queued missing-workload demo must not leave a stale Query Store recovery record.'
    }
    finally {
        try { Invoke-Query "INSERT ops.M06QueryStoreRaceSync (Actor) SELECT N'Release' WHERE NOT EXISTS (SELECT 1 FROM ops.M06QueryStoreRaceSync WHERE Actor = N'Release');" | Out-Null } catch { }
        foreach ($job in @($blocker, $resetJob, $planJob) | Where-Object { $null -ne $_ }) {
            if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        try { Invoke-Query 'DROP TABLE IF EXISTS ops.M06QueryStoreRaceSync;' | Out-Null } catch { }
    }
}
catch {
    Add-Failure "Runtime validation failed: $($_.Exception.Message)"
}
finally {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    $password = $null
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (M06 Query Store recovery lifecycle is serialized)' -ForegroundColor Green
