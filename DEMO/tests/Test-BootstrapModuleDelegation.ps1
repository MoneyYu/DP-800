[CmdletBinding()]
param()

# ---------------------------------------------------------------------------
# True end-to-end regression for the dot-source parameter clobber in
# Invoke-Bootstrap.ps1.
#
# The bootstrap dot-sources Invoke-DemoModule.ps1 (to keep the [int[]] $Modules
# array intact across the delegation boundary). Dot-sourcing re-executes the
# runner's param() block in the bootstrap scope, so unless the caller's values
# are captured BEFORE the dot-source, the runner's own parameter DEFAULTS
# (-Modules @(1..11), -Server 127.0.0.1,1433, -User sa) silently overwrite the
# user's requested -Modules/-Server/-User. That would run all 11 modules against
# the wrong server/user instead of exactly what was requested.
#
# This test drives the REAL Invoke-Bootstrap.ps1 with a harmless test seam: a
# fixture copy whose Invoke-Dp800Sql.ps1 is a no-op and whose
# Invoke-DemoModule.ps1 is a capture runner that records the exact -Server,
# -User, -Database, and -Modules values it received. It proves the caller's
# values survive the dot-source (no clobber). It needs no database connectivity.
#
# The capture runner deliberately keeps the SAME param() block and defaults as
# the production runner, so a regression to the clobbering delegation would make
# the captured values fall back to those defaults and fail this test.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$realBootstrap = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$realRunner = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$sandboxRoot = Join-Path $PSScriptRoot '.bootstrap-delegation-sandbox'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { Add-Failure "$Message Expected '$Expected' but got '$Actual'." }
}
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { Add-Failure $Message } }

Write-Host 'Bootstrap -> module runner delegation end-to-end regression (dot-source clobber)'
Write-Host ''

# The capture runner mirrors the production runner's param() block exactly so a
# clobber regression falls back to these defaults and is detected. Its
# Invoke-DemoModuleRunner records what it received to $env:BOOTSTRAP_CAPTURE_FILE.
$captureRunnerBody = @'
[CmdletBinding()]
param(
    [ValidateRange(1, 11)]
    [int[]]$Modules = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
    [switch]$Force,
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [ValidateSet('AdventureGearAI')]
    [string]$Database = 'AdventureGearAI',
    [string]$ManifestPath,
    [switch]$SkipCoreBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-DemoModuleRunner {
    param(
        [int[]]$Modules = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
        [switch]$Force,
        [string]$Server = '127.0.0.1,1433',
        [string]$User = 'sa',
        [string]$Database = 'AdventureGearAI',
        [string]$ManifestPath,
        [switch]$SkipCoreBootstrap
    )

    $capturePath = $env:BOOTSTRAP_CAPTURE_FILE
    if ([string]::IsNullOrWhiteSpace($capturePath)) {
        throw 'BOOTSTRAP_CAPTURE_FILE is not set; the capture runner cannot record its inputs.'
    }

    $record = [ordered]@{
        Server           = $Server
        User             = $User
        Database         = $Database
        Modules          = @($Modules)
        ModuleCount      = @($Modules).Count
        Force            = [bool]$Force
        SkipCoreBootstrap = [bool]$SkipCoreBootstrap
    }
    Set-Content -LiteralPath $capturePath -Value ($record | ConvertTo-Json -Depth 5) -NoNewline
    Write-Host "CAPTURE: Server=$Server User=$User Database=$Database Modules=$(@($Modules) -join ',')"
}

# Match the production runner's dot-source guard so the main body does not run
# when Invoke-Bootstrap.ps1 dot-sources this file; the bootstrap then calls
# Invoke-DemoModuleRunner explicitly with the captured values.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DemoModuleRunner -Modules $Modules -Force:$Force -Server $Server -User $User -Database $Database -ManifestPath $ManifestPath -SkipCoreBootstrap:$SkipCoreBootstrap
}
'@

# A harmless no-op SQL runner: accepts the bootstrap's call signature and does
# nothing (no database is touched).
$noopSqlRunnerBody = @'
[CmdletBinding()]
param(
    [string]$Server,
    [string]$User,
    [string]$Database,
    [string]$InputFile,
    [switch]$SkipDatabaseGuard
)
# Intentionally a no-op: this test seam never contacts a database.
exit 0
'@

function New-DelegationFixture {
    param([string]$Name)

    $fixtureRoot = Join-Path $sandboxRoot $Name
    $bootstrapDir = Join-Path $fixtureRoot 'DEMO\bootstrap'
    $scriptsDir = Join-Path $fixtureRoot 'DEMO\scripts'
    New-Item -ItemType Directory -Path $bootstrapDir -Force | Out-Null
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

    # Real bootstrap under test.
    Copy-Item -LiteralPath $realBootstrap -Destination (Join-Path $bootstrapDir 'Invoke-Bootstrap.ps1') -Force

    # Harmless bootstrap SQL assets referenced by literal name (never executed).
    foreach ($sql in '00-create-adventuregear-database.sql', '01-initialize-adventuregear-demo.sql', 'report-legacy-databases.sql') {
        Set-Content -LiteralPath (Join-Path $bootstrapDir $sql) -Value 'PRINT 1;' -NoNewline
    }

    # Test seams: no-op SQL runner + capture module runner.
    Set-Content -LiteralPath (Join-Path $scriptsDir 'Invoke-Dp800Sql.ps1') -Value $noopSqlRunnerBody -NoNewline
    Set-Content -LiteralPath (Join-Path $scriptsDir 'Invoke-DemoModule.ps1') -Value $captureRunnerBody -NoNewline

    return (Join-Path $bootstrapDir 'Invoke-Bootstrap.ps1')
}

function Invoke-BootstrapCapture {
    param(
        [string]$FixtureBootstrap,
        [string]$CaptureFile,
        [string]$Server,
        [string]$User,
        [int[]]$Modules
    )

    if (Test-Path -LiteralPath $CaptureFile) { Remove-Item -LiteralPath $CaptureFile -Force }

    # Invoke the real bootstrap in a child process via the call operator so the
    # -Modules [int[]] array is passed natively (as it is in real in-process
    # usage), instead of through the pwsh -File CLI which mangles comma-separated
    # arrays (e.g. "2,9,11" -> the single integer 2911).
    $command = "& '$FixtureBootstrap' -Server '$Server' -User '$User'"
    if ($PSBoundParameters.ContainsKey('Modules') -and $Modules.Count -gt 0) {
        $command += " -Modules $($Modules -join ',')"
    }

    $originalCapture = $env:BOOTSTRAP_CAPTURE_FILE
    $env:BOOTSTRAP_CAPTURE_FILE = $CaptureFile
    try {
        $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String
    }
    finally {
        $env:BOOTSTRAP_CAPTURE_FILE = $originalCapture
    }

    $capture = $null
    if (Test-Path -LiteralPath $CaptureFile) {
        $capture = Get-Content -LiteralPath $CaptureFile -Raw | ConvertFrom-Json
    }

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
        Capture  = $capture
    }
}

try {
    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }

    $fixtureBootstrap = New-DelegationFixture -Name 'capture'
    $captureFile = Join-Path $sandboxRoot 'capture.json'

    # --- Scenario 1: custom Server/User and a partial multi-element -Modules ---
    # Requested M02,M09,M11 with custom Server/User must reach the runner EXACTLY
    # as requested. This is the precise scenario the clobber bug breaks.
    $s1 = Invoke-BootstrapCapture -FixtureBootstrap $fixtureBootstrap -CaptureFile $captureFile -Server 'e2e-server' -User 'e2e-user' -Modules 2, 9, 11

    Assert-Equal -Actual $s1.ExitCode -Expected 0 -Message "Scenario 1 bootstrap must exit 0. Output: $($s1.Output)"
    if ($null -eq $s1.Capture) {
        Add-Failure "Scenario 1: the runner was never invoked (no capture written). Output: $($s1.Output)"
    }
    else {
        Assert-Equal -Actual $s1.Capture.Server -Expected 'e2e-server' -Message 'Scenario 1: custom -Server must reach the runner (not the runner default 127.0.0.1,1433).'
        Assert-Equal -Actual $s1.Capture.User -Expected 'e2e-user' -Message 'Scenario 1: custom -User must reach the runner (not the runner default sa).'
        Assert-Equal -Actual $s1.Capture.Database -Expected 'AdventureGearAI' -Message 'Scenario 1: -Database must reach the runner as AdventureGearAI.'
        Assert-Equal -Actual (@($s1.Capture.Modules) -join ',') -Expected '2,9,11' -Message 'Scenario 1: exactly the requested modules M02,M09,M11 must reach the runner.'
        Assert-Equal -Actual $s1.Capture.ModuleCount -Expected 3 -Message 'Scenario 1: the runner must receive 3 modules, NOT all 11 (clobber would send 11).'
        Assert-True -Condition ([bool]$s1.Capture.SkipCoreBootstrap) -Message 'Scenario 1: the runner must be called with -SkipCoreBootstrap (core already provisioned).'
    }

    # --- Dependency resolution: the exact modules that reached the runner must ---
    # resolve to the full transitive closure 1,2,9,10,11 via the REAL runner.
    . $realRunner
    if ($null -ne $s1.Capture) {
        $plan = @(Resolve-DemoModuleExecutionPlan -Requested (@($s1.Capture.Modules)))
        Assert-Equal -Actual ($plan -join ',') -Expected '1,2,9,10,11' -Message 'The captured modules M02,M09,M11 must resolve to dependency order 1,2,9,10,11.'
        Assert-True -Condition ($plan.Count -eq 5) -Message 'The resolved plan for M02,M09,M11 must contain 5 modules (not all 11).'
    }

    # --- Scenario 2: a different custom Server/User and a single module ---------
    # Reinforces that Server/User preservation is not tied to a specific value.
    $captureFile2 = Join-Path $sandboxRoot 'capture2.json'
    $s2 = Invoke-BootstrapCapture -FixtureBootstrap $fixtureBootstrap -CaptureFile $captureFile2 -Server 'sql.contoso.local,14330' -User 'trainer' -Modules 5

    Assert-Equal -Actual $s2.ExitCode -Expected 0 -Message "Scenario 2 bootstrap must exit 0. Output: $($s2.Output)"
    if ($null -eq $s2.Capture) {
        Add-Failure "Scenario 2: the runner was never invoked (no capture written). Output: $($s2.Output)"
    }
    else {
        Assert-Equal -Actual $s2.Capture.Server -Expected 'sql.contoso.local,14330' -Message 'Scenario 2: custom -Server must be preserved through delegation.'
        Assert-Equal -Actual $s2.Capture.User -Expected 'trainer' -Message 'Scenario 2: custom -User must be preserved through delegation.'
        Assert-Equal -Actual (@($s2.Capture.Modules) -join ',') -Expected '5' -Message 'Scenario 2: exactly the requested module M05 must reach the runner.'
        Assert-Equal -Actual $s2.Capture.ModuleCount -Expected 1 -Message 'Scenario 2: the runner must receive exactly 1 module.'
    }

    # --- Scenario 3: no -Modules => the runner must NOT be invoked at all -------
    $captureFile3 = Join-Path $sandboxRoot 'capture3.json'
    $s3 = Invoke-BootstrapCapture -FixtureBootstrap $fixtureBootstrap -CaptureFile $captureFile3 -Server 'core-only' -User 'core-user'

    Assert-Equal -Actual $s3.ExitCode -Expected 0 -Message "Scenario 3 bootstrap must exit 0. Output: $($s3.Output)"
    Assert-True -Condition ($null -eq $s3.Capture) -Message 'Scenario 3: with no -Modules the bootstrap must NOT delegate to the runner (core-only run).'
}
finally {
    if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (bootstrap -> runner delegation preserves exact Modules/Server/User)' -ForegroundColor Green
exit 0
