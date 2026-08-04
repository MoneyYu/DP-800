[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

# ---------------------------------------------------------------------------
# Single orchestrator for the unified AdventureGearAI demo validation. It runs
# every static and runtime test in a deterministic order and produces one
# summary with an aggregate pass/fail exit code.
#
# Required environment (this repository ships and expects a local SQL Server
# 2025 container): sqlcmd, docker, the running mssql2025 container, and its
# MSSQL_SA_PASSWORD. The orchestrator FAILS FAST if any of these is missing -
# it does not silently skip local required infrastructure. Individual optional
# external features (Azure OpenAI endpoints, full-text search) are skipped by
# the demo scripts themselves and never block validation.
#
# The SA password is read from the container and exported to the child test
# processes in-process only (SQLCMDPASSWORD / DP800_SQL_PASSWORD); it is never
# written to disk, embedded, or echoed.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $testsRoot '..\..')).ProviderPath
$selfName = Split-Path -Leaf $PSCommandPath

Write-Host '=================================================================='
Write-Host ' Unified AdventureGearAI demo - full validation orchestrator'
Write-Host '=================================================================='
Write-Host ''

# --- Enforce required local infrastructure (fail fast, do not skip) ----------
$fatal = [System.Collections.Generic.List[string]]::new()
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) { $fatal.Add('sqlcmd was not found on PATH.') }
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) { $fatal.Add('docker was not found on PATH.') }
if ($docker) {
    $running = (& docker ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
    if (-not $running) { $fatal.Add("The required SQL Server container '$Container' is not running.") }
}
$password = $null
if ($docker -and $fatal.Count -eq 0) {
    $password = (& docker exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($password)) { $fatal.Add("MSSQL_SA_PASSWORD is not set in container '$Container'.") }
}
if ($fatal.Count -gt 0) {
    Write-Host 'FATAL: required validation infrastructure is unavailable in an environment that is expected to provide it:' -ForegroundColor Red
    foreach ($f in $fatal) { Write-Host "  - $f" -ForegroundColor Red }
    exit 2
}

# Confirm connectivity before running the suite.
$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
[Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
[Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

try {
    $ping = & $sqlcmd.Source -S $Server -U $User -C -b -h -1 -W -Q 'SELECT 1;' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FATAL: could not connect to '$Server' as '$User': $($ping.Trim())" -ForegroundColor Red
        exit 2
    }

    # --- Secret leak check: the live SA password must not be committed -------
    $leaks = [System.Collections.Generic.List[string]]::new()
    $trackedText = @(& git -C $repoRoot ls-files -- DEMO 2>$null) | Where-Object {
        $_ -match '\.(ps1|psm1|sql|json|md|xml|yml|yaml|sqlproj|txt|config)$'
    }
    foreach ($rel in $trackedText) {
        $full = Join-Path $repoRoot $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $content = Get-Content -LiteralPath $full -Raw
        if ($content -and $content.Contains($password)) { $leaks.Add($rel) }
    }
    if ($leaks.Count -gt 0) {
        Write-Host 'FATAL: the live SA password appears in committed files:' -ForegroundColor Red
        foreach ($l in $leaks) { Write-Host "  - $l" -ForegroundColor Red }
        exit 2
    }
    Write-Host "Environment OK: sqlcmd + '$Container' reachable; SA password is not committed under DEMO." -ForegroundColor Green
    Write-Host ''

    # --- Deterministic test order: fast static checks first, then runtime ----
    $orderedTests = @(
        'Test-UnifiedDemo.ps1'
        'Test-UnifiedDemoHarness.ps1'
        'Test-UnifiedDemoDocs.ps1'
        'Test-UnifiedDemoStaticAnalysis.ps1'
        'Test-DemoLocalization.ps1'
        'Test-CoreBootstrap.ps1'
        'Test-DemoModuleRunner.ps1'
        'Test-BootstrapModuleDelegation.ps1'
        'Test-UnifiedDemoM01ToM06.ps1'
        'Test-UnifiedApiSearchRag.ps1'
        'Test-UnifiedDemoResets.ps1'
        'Test-CoreBootstrapRuntime.ps1'
        'Test-DemoModuleRunnerRuntime.ps1'
        'Test-UnifiedDemoM01ToM06Runtime.ps1'
        'Test-UnifiedApiSearchRagRuntime.ps1'
        'Test-UnifiedDemoResetsRuntime.ps1'
        'Test-UnifiedDemoProductionFlowRuntime.ps1'
        'Test-UnifiedDemoM06ConcurrencyRuntime.ps1'
        'Test-DemoLocalizationRuntime.ps1'
    )

    # Include any additional Test-*.ps1 not explicitly listed (excluding self),
    # so newly added tests are never silently omitted.
    $discovered = Get-ChildItem -LiteralPath $testsRoot -Filter 'Test-*.ps1' | Sort-Object Name | ForEach-Object { $_.Name }
    foreach ($name in $discovered) {
        if ($name -ne $selfName -and ($orderedTests -notcontains $name)) { $orderedTests += $name }
    }

    $candidateArgs = @{ Server = $Server; User = $User; Container = $Container }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($name in $orderedTests) {
        $path = Join-Path $testsRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $results.Add([pscustomobject]@{ Test = $name; Status = 'MISSING'; Seconds = 0 })
            continue
        }

        # Pass only the parameters the target script actually declares.
        $supported = @{}
        try {
            $cmd = Get-Command $path -ErrorAction Stop
            foreach ($key in $candidateArgs.Keys) {
                if ($cmd.Parameters.ContainsKey($key)) { $supported[$key] = $candidateArgs[$key] }
            }
        }
        catch { }

        $argList = @('-NoProfile', '-File', $path)
        foreach ($key in $supported.Keys) { $argList += "-$key"; $argList += [string]$supported[$key] }

        Write-Host ("[RUN ] {0}" -f $name) -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $output = & pwsh @argList 2>&1 | Out-String
        $code = $LASTEXITCODE
        $sw.Stop()

        $status = if ($code -ne 0) { 'FAIL' }
        elseif ($output -match '(?m)^\s*SKIP:' -and $output -notmatch '(?m)^PASS \(') { 'SKIP' }
        else { 'PASS' }

        $color = switch ($status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
        Write-Host ("[{0}] {1} ({2:n1}s)" -f $status, $name, $sw.Elapsed.TotalSeconds) -ForegroundColor $color
        if ($status -ne 'PASS') {
            foreach ($line in ($output -split "`r?`n" | Where-Object { $_ -match '(?i)FAIL|SKIP:|error|Exception' } | Select-Object -First 12)) {
                Write-Host "        $line" -ForegroundColor $color
            }
        }
        $results.Add([pscustomobject]@{ Test = $name; Status = $status; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) })
    }

    Write-Host ''
    Write-Host '------------------------------ SUMMARY ---------------------------'
    $results | Format-Table -AutoSize | Out-String | Write-Host
    $passed = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
    $failed = @($results | Where-Object { $_.Status -in @('FAIL', 'MISSING') }).Count
    $skipped = @($results | Where-Object { $_.Status -eq 'SKIP' }).Count
    Write-Host ("Total: {0}   Passed: {1}   Failed: {2}   Skipped: {3}" -f $results.Count, $passed, $failed, $skipped)

    if ($skipped -gt 0) {
        # The container/sqlcmd/password were verified present, so a whole-test
        # skip means required validation did not run: treat it as a failure.
        Write-Host 'One or more tests skipped despite required infrastructure being available.' -ForegroundColor Red
    }

    if ($failed -gt 0 -or $skipped -gt 0) {
        Write-Host 'RESULT: FAIL' -ForegroundColor Red
        exit 1
    }
    Write-Host 'RESULT: PASS (all unified demo validation checks succeeded)' -ForegroundColor Green
    exit 0
}
finally {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $originalDpPassword, 'Process')
    $password = $null
    # Best-effort cleanup of any sandbox directories left by interrupted tests.
    foreach ($sandbox in '.sandbox', '.runner-runtime-sandbox', '.apisearchrag-sandbox') {
        $dir = Join-Path $testsRoot $sandbox
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    [System.GC]::Collect()
}
