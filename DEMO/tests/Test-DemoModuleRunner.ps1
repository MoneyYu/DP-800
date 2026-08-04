[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$scriptsRoot = Join-Path $demoRoot 'scripts'
$runnerScript = Join-Path $scriptsRoot 'Invoke-DemoModule.ps1'
$sqlRunnerScript = Join-Path $scriptsRoot 'Invoke-Dp800Sql.ps1'
$guardSql = Join-Path $scriptsRoot 'Assert-DemoDatabase.sql'
$manifestJson = Join-Path $scriptsRoot 'module-manifest.json'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$sandboxRoot = Join-Path $PSScriptRoot '.runner-static-sandbox'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { Add-Failure "$Message Expected '$Expected' but got '$Actual'." }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Add-Failure $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try { & $Action; Add-Failure "$Message (no exception thrown)." }
    catch { if ("$($_.Exception.Message)" -notmatch $Pattern) { Add-Failure "$Message Actual: $($_.Exception.Message)" } }
}
function Get-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Failure "Missing required file: $Path"; return $null }
    return Get-Content -LiteralPath $Path -Raw
}
function Assert-Present {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($null -eq $Text) { return }
    if ($Text -notmatch $Pattern) { Add-Failure $Message }
}
function Assert-Absent {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($null -eq $Text) { return }
    if ($Text -match $Pattern) { Add-Failure $Message }
}

Write-Host 'Dependency-aware module runner static/unit tests'
Write-Host ''

# Dot-source the runner: the InvocationName='.' guard means the main body does
# not run, so the pure helper functions are available without a database.
. $runnerScript

try {
    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }

    # --- 1) Dependency resolution --------------------------------------------
    Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested 11) -join ',') -Expected '1,9,10,11' -Message 'Requesting M11 must resolve M01,M09,M10,M11 in dependency order.'
    Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested 10) -join ',') -Expected '1,9,10' -Message 'Requesting M10 must resolve M01,M09,M10.'
    Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested 3) -join ',') -Expected '1,3' -Message 'Requesting M03 must resolve M01,M03.'
    Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested @(4, 2)) -join ',') -Expected '1,2,4' -Message 'Requesting M04,M02 must resolve to ascending dependency order 1,2,4.'
    Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested @(1..11)) -join ',') -Expected '1,2,3,4,5,6,7,8,9,10,11' -Message 'Requesting all modules must produce ascending 1..11.'
    Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested 1) -join ',') -Expected '1' -Message 'Requesting M01 must resolve to only M01 (core is implicit).'
    Assert-Throws -Action { Resolve-DemoModuleExecutionPlan -Requested 12 } -Pattern 'Unknown module' -Message 'Resolving an out-of-range module must throw.'

    # --- 2) Wrong-database guard (read-only, explicit) -----------------------
    $guardText = Get-Text -Path $guardSql
    Assert-Present -Text $guardText -Pattern "(?i)DB_NAME\(\)" -Message 'Guard must inspect DB_NAME().'
    Assert-Present -Text $guardText -Pattern "AdventureGearAI" -Message 'Guard must require AdventureGearAI.'
    Assert-Present -Text $guardText -Pattern "(?i)ops\.DemoEnvironment" -Message 'Guard must verify the ops.DemoEnvironment marker.'
    Assert-Present -Text $guardText -Pattern "(?i)RAISERROR\(" -Message 'Guard must RAISERROR on failure.'
    Assert-Present -Text $guardText -Pattern "16,\s*1" -Message 'Guard must raise a severity-16 error so sqlcmd -b aborts.'
    Assert-Absent -Text $guardText -Pattern '(?im)^\s*(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|MERGE)\b' -Message 'Guard must be read-only (no DML/DDL).'

    $sqlRunnerText = Get-Text -Path $sqlRunnerScript
    Assert-Present -Text $sqlRunnerText -Pattern "(?i)\`$Database\s*=\s*'AdventureGearAI'" -Message 'Invoke-Dp800Sql default Database must be AdventureGearAI.'
    Assert-Present -Text $sqlRunnerText -Pattern "(?i)\[switch\]\`$SkipDatabaseGuard" -Message 'Invoke-Dp800Sql must expose a -SkipDatabaseGuard switch.'
    Assert-Present -Text $sqlRunnerText -Pattern "(?i)Assert-DemoDatabase\.sql" -Message 'Invoke-Dp800Sql must run the Assert-DemoDatabase.sql guard.'
    Assert-Present -Text $sqlRunnerText -Pattern "(?i)Database\s+-ne\s+'master'\s+-and\s+-not\s+\`$SkipDatabaseGuard" -Message 'Invoke-Dp800Sql must guard every non-master target unless explicitly skipped.'

    # --- 2b) Runner password-resolution static assertions --------------------
    # Verify Invoke-DemoModule.ps1 implements the same resolution semantics as
    # Invoke-Dp800Sql.ps1: DP800_SQL_PASSWORD preferred, then SQLCMDPASSWORD,
    # then secure prompt; SQLCMDPASSWORD set only in process scope; finally restores.
    $runnerText = Get-Text -Path $runnerScript
    Assert-Present -Text $runnerText -Pattern "(?i)DP800_SQL_PASSWORD" -Message 'Runner must reference DP800_SQL_PASSWORD for password resolution.'
    Assert-Present -Text $runnerText -Pattern "(?i)env:DP800_SQL_PASSWORD" -Message 'Runner must prefer $env:DP800_SQL_PASSWORD as primary password source.'
    Assert-Present -Text $runnerText -Pattern "(?i)env:SQLCMDPASSWORD" -Message 'Runner must fall back to $env:SQLCMDPASSWORD when DP800_SQL_PASSWORD is absent.'
    Assert-Present -Text $runnerText -Pattern "(?i)Read-Host.*AsSecureString" -Message 'Runner must fall back to a secure prompt when no env var is set.'
    Assert-Present -Text $runnerText -Pattern "(?i)SetEnvironmentVariable\('SQLCMDPASSWORD'" -Message 'Runner must set SQLCMDPASSWORD in the process scope for sqlcmd state calls.'
    Assert-Present -Text $runnerText -Pattern "(?i)\[Environment\]::SetEnvironmentVariable\('SQLCMDPASSWORD',\s*\`$originalSqlCmdPassword" -Message 'Runner must restore the original SQLCMDPASSWORD value in the finally block.'
    Assert-Present -Text $runnerText -Pattern "(?i)\`$temporaryPassword\s*=\s*\`$null" -Message 'Runner must clear the temporary plaintext password in the finally block.'

    # --- 3) State-transition SQL (secure, no arbitrary interpolation) ---------
    $runningSql = Get-DemoModuleStateUpdateSql -Module 9 -Status 'Running'
    Assert-Present -Text $runningSql -Pattern "Status=N'Running'" -Message 'Running transition must set Status=Running.'
    Assert-Present -Text $runningSql -Pattern "StartedAtUtc=SYSUTCDATETIME\(\)" -Message 'Running transition must stamp StartedAtUtc.'
    Assert-Present -Text $runningSql -Pattern "WHERE ModuleNumber=9;" -Message 'Running transition must scope to the validated module number.'

    $completedSql = Get-DemoModuleStateUpdateSql -Module 10 -Status 'Completed'
    Assert-Present -Text $completedSql -Pattern "Status=N'Completed'" -Message 'Completed transition must set Status=Completed.'
    Assert-Present -Text $completedSql -Pattern "CompletedAtUtc=SYSUTCDATETIME\(\)" -Message 'Completed transition must stamp CompletedAtUtc.'

    $failedSql = Get-DemoModuleStateUpdateSql -Module 3 -Status 'Failed' -ErrorText "boom '; DROP TABLE ops.DemoModuleState; --`nsecond line `$(evil)"
    Assert-Present -Text $failedSql -Pattern "Status=N'Failed'" -Message 'Failed transition must set Status=Failed.'
    Assert-Present -Text $failedSql -Pattern "LastError=N'boom ''; DROP TABLE ops.DemoModuleState; -- second line \`$\(evil\)'" -Message 'Failed transition must single-quote-escape and single-line the error text so it cannot break out of the literal.'
    Assert-Absent -Text $failedSql -Pattern "(?m)`n" -Message 'Failed transition SQL must be a single line (newlines collapsed).'
    Assert-Throws -Action { Get-DemoModuleStateUpdateSql -Module 99 -Status 'Running' } -Pattern 'Invalid module number' -Message 'State update must reject out-of-range module numbers.'

    # --- 4) Skip / Force decision --------------------------------------------
    Assert-Equal -Actual (Test-DemoModuleShouldRun -CurrentStatus 'Completed') -Expected $false -Message 'A Completed module must be skipped without -Force.'
    Assert-Equal -Actual (Test-DemoModuleShouldRun -CurrentStatus 'Completed' -Force) -Expected $true -Message 'A Completed module must re-run with -Force.'
    Assert-Equal -Actual (Test-DemoModuleShouldRun -CurrentStatus 'NotStarted') -Expected $true -Message 'A NotStarted module must run.'
    Assert-Equal -Actual (Test-DemoModuleShouldRun -CurrentStatus 'Failed') -Expected $true -Message 'A Failed module must run.'
    Assert-Equal -Actual (Test-DemoModuleShouldRun -CurrentStatus 'Running') -Expected $true -Message 'A Running module must run (retry).'

    # --- 5) Missing / incompatible manifest failures -------------------------
    $prodManifest = Read-DemoModuleManifest -Path $manifestJson
    Assert-Equal -Actual (($prodManifest.Keys | Sort-Object) -join ',') -Expected '1,2,3,4,5,6,7,8,9,10,11' -Message 'Production manifest must list all 11 modules.'
    # Migration-tolerant readiness: modules migrated to AdventureGearAI flip to
    # ready=true and must resolve at least one common/local setup script; modules
    # still on the legacy layout stay ready=false and must refuse to run.
    foreach ($module in 1..11) {
        if ($prodManifest[$module].Ready) {
            $resolvedReady = @(Get-DemoModuleSetupScripts -Manifest $prodManifest -Module $module -Scope local)
            Assert-True -Condition ($resolvedReady.Count -ge 1) -Message "Ready manifest M$('{0:d2}' -f $module) must resolve at least one common/local setup script."
        }
        else {
            Assert-Throws -Action { Get-DemoModuleSetupScripts -Manifest $prodManifest -Module $module -Scope local } -Pattern 'not populated/migrated yet' -Message "Not-ready manifest M$('{0:d2}' -f $module) must refuse to run legacy scripts."
        }
    }
    # Exercise the not-ready refusal path explicitly (holds even once every
    # production module is migrated) via a synthetic ready=false manifest.
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
    $notReadyManifestPath = Join-Path $sandboxRoot 'not-ready-manifest.json'
    Set-Content -LiteralPath $notReadyManifestPath -Value (@{ schemaVersion = '1.0.0'; modules = @(@{ module = 1; ready = $false; setup = @{ common = @(); local = @(); azure = @() } }) } | ConvertTo-Json -Depth 6) -NoNewline
    $notReadyManifest = Read-DemoModuleManifest -Path $notReadyManifestPath
    Assert-Throws -Action { Get-DemoModuleSetupScripts -Manifest $notReadyManifest -Module 1 -Scope local } -Pattern 'not populated/migrated yet' -Message 'A not-ready module must fail clearly instead of running legacy scripts.'
    $emptyManifest = @{}
    Assert-Throws -Action { Get-DemoModuleSetupScripts -Manifest $emptyManifest -Module 5 -Scope local } -Pattern 'no setup manifest entry' -Message 'An absent manifest entry must fail clearly.'

    # --- 6) Bootstrap wiring -------------------------------------------------
    $bootstrapText = Get-Text -Path $bootstrapScript
    Assert-Present -Text $bootstrapText -Pattern "Invoke-DemoModule\.ps1" -Message 'Bootstrap must wire the module runner.'
    Assert-Present -Text $bootstrapText -Pattern "(?i)-SkipCoreBootstrap" -Message 'Bootstrap must call the runner with -SkipCoreBootstrap to avoid recursion.'
    Assert-Present -Text $bootstrapText -Pattern "(?i)Modules\.Count\s*-gt\s*0" -Message 'Bootstrap must delegate only when modules are requested.'
    Assert-Present -Text $bootstrapText -Pattern "(?i)-SkipDatabaseGuard" -Message 'Bootstrap init call must use -SkipDatabaseGuard (trusted setup path).'
    Assert-Absent -Text $bootstrapText -Pattern "per-module runner is not available" -Message 'Bootstrap must no longer throw the retired unavailable-runner message.'

    # --- 7) No azure / interactive scripts in a normal local run -------------
    $fixtureDir = Join-Path $sandboxRoot 'ready-module'
    New-Item -ItemType Directory -Path (Join-Path $fixtureDir 'common') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureDir 'local') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureDir 'azure') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fixtureDir 'common\01-data.sql') -Value 'PRINT 1;' -NoNewline
    Set-Content -LiteralPath (Join-Path $fixtureDir 'local\01-inspect.sql') -Value 'PRINT 1;' -NoNewline
    Set-Content -LiteralPath (Join-Path $fixtureDir 'azure\01-external.sql') -Value 'PRINT 1;' -NoNewline
    $fixtureManifestPath = Join-Path $sandboxRoot 'module-manifest.json'
    $fixtureManifest = @{
        schemaVersion = '1.0.0'
        modules       = @(
            @{ module = 6; ready = $true; setup = @{
                    common = @('ready-module/common/01-data.sql')
                    local  = @('ready-module/local/01-inspect.sql')
                    azure  = @('ready-module/azure/01-external.sql')
                }
            }
        )
    }
    Set-Content -LiteralPath $fixtureManifestPath -Value ($fixtureManifest | ConvertTo-Json -Depth 6) -NoNewline

    $readyManifest = Read-DemoModuleManifest -Path $fixtureManifestPath
    $selected = @(Get-DemoModuleSetupScripts -Manifest $readyManifest -Module 6 -Scope local)
    Assert-Equal -Actual $selected.Count -Expected 2 -Message 'Local run must select exactly the common+local scripts.'
    Assert-True -Condition (@($selected | Where-Object { $_ -match 'azure' }).Count -eq 0) -Message 'Local run must never include azure scripts.'
    Assert-True -Condition (@($selected | Where-Object { $_ -match 'common' }).Count -eq 1) -Message 'Local run must include the common setup script.'
    Assert-True -Condition (@($selected | Where-Object { $_ -match 'local' }).Count -eq 1) -Message 'Local run must include the local setup script.'

    # Incompatible manifest: a listed script that does not exist must fail.
    $missingManifestPath = Join-Path $sandboxRoot 'missing-manifest.json'
    $missingManifest = @{ modules = @(@{ module = 7; ready = $true; setup = @{ common = @('does/not/exist.sql'); local = @(); azure = @() } }) }
    Set-Content -LiteralPath $missingManifestPath -Value ($missingManifest | ConvertTo-Json -Depth 6) -NoNewline
    $readyMissing = Read-DemoModuleManifest -Path $missingManifestPath
    Assert-Throws -Action { Get-DemoModuleSetupScripts -Manifest $readyMissing -Module 7 -Scope local } -Pattern 'does not exist \(incompatible manifest\)' -Message 'A ready module whose script is missing must fail as an incompatible manifest.'

    # --- 8) Hybrid integration: Bootstrap delegates via dot-source, not child process ---------
    # The bug: & pwsh -File passes [int[]] as a concatenated string, losing elements.
    # The fix: Invoke-Bootstrap.ps1 must dot-source Invoke-DemoModule.ps1 and call
    # Invoke-DemoModuleRunner directly so [int[]] is passed intact.
    Write-Host ''
    Write-Host '--- Section 8: Hybrid integration - Bootstrap dot-source delegation'
    $bootstrapSource = Get-Text -Path $bootstrapScript
    # Must NOT spawn a child process to invoke the module runner.
    Assert-Absent -Text $bootstrapSource -Pattern '(?i)pwsh[^`n]*-File[^`n]*Invoke-DemoModule' -Message 'Invoke-Bootstrap must NOT spawn a child pwsh -File process to invoke the module runner (multi-element int[] values would be lost).'
    # Must dot-source the runner file (preserves [int[]] in current process).
    Assert-Present -Text $bootstrapSource -Pattern '(?i)\.\s+\$moduleRunner' -Message 'Invoke-Bootstrap must dot-source $moduleRunner to preserve [int[]] across the boundary.'
    # Must call Invoke-DemoModuleRunner directly (not via & pwsh -File).
    Assert-Present -Text $bootstrapSource -Pattern '(?i)Invoke-DemoModuleRunner\s' -Message 'Invoke-Bootstrap must call Invoke-DemoModuleRunner directly after dot-sourcing.'

    # --- 9) [int[]] integrity: multi-element module resolution via Resolve-DemoModuleExecutionPlan ------
    # Requesting M02, M09, M11 must resolve the full transitive closure and return
    # them in dependency order: M01 (base), M02, M09, M10 (M11 depends on M10),
    # M11.  This exercises exactly the scenario that the child-process bug breaks.
    Write-Host '--- Section 9: [int[]] multi-element array resolution - Modules 2,9,11'
    $plan2_9_11 = @(Resolve-DemoModuleExecutionPlan -Requested @(2, 9, 11))
    Assert-Equal -Actual ($plan2_9_11 -join ',') -Expected '1,2,9,10,11' `
        -Message 'Requesting M02,M09,M11 must resolve transitive closure 1,2,9,10,11 in dependency order.'
    Assert-True -Condition ($plan2_9_11.Count -eq 5) `
        -Message 'Requesting M02,M09,M11 must return 5 modules in the execution plan (not 1 due to array serialization loss).'
    Assert-True -Condition ($plan2_9_11[0] -eq 1) -Message 'First module in plan for M02,M09,M11 must be M01 (base dependency).'
    Assert-True -Condition ($plan2_9_11[-1] -eq 11) -Message 'Last module in plan for M02,M09,M11 must be M11 (terminal dependency).'

    # --- 10) Invalid values rejected by Invoke-DemoModuleRunner ----------------------
    Write-Host '--- Section 10: Invalid module values rejected'
    # Invoke-DemoModuleRunner validates before any DB call, so these must throw.
    Assert-Throws -Action {
        Invoke-DemoModuleRunner -Modules @(12) -ManifestPath $missingManifestPath
    } -Pattern 'Invalid module number' -Message 'Invoke-DemoModuleRunner must reject module number 12 (> 11).'
    Assert-Throws -Action {
        Invoke-DemoModuleRunner -Modules @(0) -ManifestPath $missingManifestPath
    } -Pattern 'Invalid module number' -Message 'Invoke-DemoModuleRunner must reject module number 0 (< 1).'
    Assert-Throws -Action {
        Invoke-DemoModuleRunner -Modules @(1, 99) -ManifestPath $missingManifestPath
    } -Pattern 'Invalid module number' -Message 'Invoke-DemoModuleRunner must reject any invalid element in a mixed valid/invalid array.'
}
finally {
    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all module runner static/unit checks succeeded)' -ForegroundColor Green
exit 0
