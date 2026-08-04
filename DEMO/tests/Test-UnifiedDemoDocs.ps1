[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Documentation regression harness for the unified AdventureGearAI demo flow.
#
# This complements Test-UnifiedDemo.ps1 (which validates scripts/assets) by
# checking that the prose in DEMO/README.md, every module README, the trainer
# teaching guide, and the demo-environment reference all consistently teach ONE
# AdventureGearAI database and the domain-centric cumulative/hybrid module flow.
#
# It validates:
#   * commands/targets  - no runnable command targets a legacy DP800_Mxx database;
#   * required sections - DEMO/README.md covers the story, schemas, bootstrap,
#                         runner, Force, resets, ops tables, and dependency flow;
#   * legacy prose      - any DP800_Mxx mention is framed as manual-cleanup prose
#                         that is never automatically deleted;
#   * module READMEs    - each M01..M11 README targets AdventureGearAI through the
#                         runner with its own module number;
#   * teaching guide    - references the runner, AdventureGearAI, and ops tables.
# ---------------------------------------------------------------------------

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$docsRoot = Join-Path $repoRoot 'docs'
$testsRoot = Join-Path $demoRoot 'tests'
$topLevelReadme = Join-Path $demoRoot 'README.md'
$teachingGuide = Join-Path $docsRoot 'teaching-guide.md'
$demoEnvironment = Join-Path $docsRoot 'demo-environment.md'

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

function Resolve-RepoPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($repoRoot.Length).TrimStart('\')
    }
    return $full
}

function Get-FileText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing required doc: $(Resolve-RepoPath -Path $Path)"
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw
}

function Test-DocContains {
    param([string]$Path, [string]$Pattern, [string]$FailureMessage)
    $text = Get-FileText -Path $Path
    if ($null -eq $text) { return }
    if ($text -notmatch $Pattern) { Add-Failure $FailureMessage }
}

# Legacy-cleanup prose markers (mirrors Test-UnifiedDemo.ps1): a line may mention
# a DP800_Mxx database only when it is explicitly framed as legacy manual cleanup.
$script:legacyCleanupProseMarkers = @(
    'legacy'
    'manual cleanup'
    'not automatically deleted'
    'never automatically deleted'
    'not automatically dropped'
    'never automatically dropped'
    'never dropped'
)

function Test-IsLegacyCleanupProse {
    param([string]$Line)
    foreach ($marker in $script:legacyCleanupProseMarkers) {
        if ($Line -match [regex]::Escape($marker)) { return $true }
    }
    return $false
}

# A "command" line is one that would be executed by a trainer: it invokes a demo
# script or passes an execution/connection target. Such lines must never mention a
# legacy DP800_Mxx database.
function Test-IsCommandLine {
    param([string]$Line)
    return ($Line -match '(?i)\.ps1\b' -or
            $Line -match '(?i)-Database\b' -or
            $Line -match '(?i)-InputFile\b' -or
            $Line -match '(?i)Invoke-(Bootstrap|DemoModule|Dp800Sql)')
}

# Enforce, line-by-line, that any DP800_Mxx mention is legacy-cleanup prose and
# never appears on an executable command line.
function Test-LegacyProseAllowance {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing required doc: $(Resolve-RepoPath -Path $Path)"
        return
    }
    $lines = Get-Content -LiteralPath $Path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -notmatch 'DP800_M\d{2}') { continue }

        if (Test-IsCommandLine -Line $line) {
            Add-Failure "$(Resolve-RepoPath -Path $Path):$($i + 1) references a legacy DP800_Mxx database on an executable command line."
            continue
        }

        if (-not (Test-IsLegacyCleanupProse -Line $line)) {
            Add-Failure "$(Resolve-RepoPath -Path $Path):$($i + 1) mentions a DP800_Mxx database without legacy manual-cleanup framing."
        }
    }
}

Write-Host 'Unified demo documentation regression harness'
Write-Host "Repository root: $repoRoot"
Write-Host ''

# ---------------------------------------------------------------------------
# 1) DEMO/README.md required sections.
# ---------------------------------------------------------------------------
$requiredReadmeSections = @(
    @{ Pattern = 'AdventureGear AI Commerce'; Message = 'DEMO/README.md is missing the AdventureGear AI Commerce story heading.' },
    @{ Pattern = '(?s)`catalog`.*`sales`.*`customer`.*`security`.*`ops`.*`api`.*`search`.*`ai`'; Message = 'DEMO/README.md does not document the eight domain schemas catalog/sales/customer/security/ops/api/search/ai in order.' },
    @{ Pattern = 'Core-only bootstrap'; Message = 'DEMO/README.md is missing the core-only bootstrap section.' },
    @{ Pattern = 'Invoke-Bootstrap\.ps1'; Message = 'DEMO/README.md does not mention Invoke-Bootstrap.ps1.' },
    @{ Pattern = 'Invoke-Bootstrap\.ps1 -Modules'; Message = 'DEMO/README.md does not show running modules via Invoke-Bootstrap.ps1 -Modules.' },
    @{ Pattern = 'Invoke-DemoModule\.ps1'; Message = 'DEMO/README.md does not mention Invoke-DemoModule.ps1.' },
    @{ Pattern = '-Force'; Message = 'DEMO/README.md does not document -Force re-runs.' },
    @{ Pattern = 'ops\.DemoEnvironment'; Message = 'DEMO/README.md does not explain ops.DemoEnvironment.' },
    @{ Pattern = 'ops\.DemoModuleState'; Message = 'DEMO/README.md does not explain ops.DemoModuleState.' },
    @{ Pattern = '(?i)prerequisit'; Message = 'DEMO/README.md does not explain prerequisite auto-resolution.' },
    @{ Pattern = '(?i)cumulative'; Message = 'DEMO/README.md does not describe the cumulative M01 -> M11 path.' },
    @{ Pattern = '(?i)independent module'; Message = 'DEMO/README.md does not describe the independent module path.' },
    @{ Pattern = 'Module reset'; Message = 'DEMO/README.md does not document the scoped module reset workflow.' },
    @{ Pattern = 'Reset-AdventureGearAI\.ps1'; Message = 'DEMO/README.md does not document the full reset wrapper Reset-AdventureGearAI.ps1.' },
    @{ Pattern = '(?i)manual cleanup'; Message = 'DEMO/README.md does not frame legacy DP800_Mxx databases as manual cleanup candidates.' },
    @{ Pattern = '(?i)never automatically deleted'; Message = 'DEMO/README.md does not state legacy databases are never automatically deleted.' }
)

foreach ($section in $requiredReadmeSections) {
    Test-DocContains -Path $topLevelReadme -Pattern $section.Pattern -FailureMessage $section.Message
}

# DEMO/README.md must not describe eleven per-module databases.
$readmeText = Get-FileText -Path $topLevelReadme
if ($null -ne $readmeText -and $readmeText -match '(?i)DP800_M01[^\n]*through[^\n]*DP800_M11') {
    foreach ($line in ($readmeText -split "\r?\n")) {
        if ($line -match '(?i)DP800_M01[^\n]*through[^\n]*DP800_M11' -and -not (Test-IsLegacyCleanupProse -Line $line)) {
            Add-Failure 'DEMO/README.md still describes creating DP800_M01 through DP800_M11 outside legacy-cleanup prose.'
        }
    }
}

# ---------------------------------------------------------------------------
# 2) Module READMEs: each targets AdventureGearAI via the runner with its own
#    module number, and never targets a legacy DP800_Mxx database on a command.
# ---------------------------------------------------------------------------
foreach ($n in 1..11) {
    $moduleName = 'M{0:d2}' -f $n
    $moduleReadme = Join-Path $demoRoot (Join-Path $moduleName 'README.md')
    if (-not (Test-Path -LiteralPath $moduleReadme -PathType Leaf)) {
        Add-Failure "Missing module README: $(Resolve-RepoPath -Path $moduleReadme)"
        continue
    }

    Test-DocContains -Path $moduleReadme -Pattern 'AdventureGearAI' `
        -FailureMessage "$moduleName README does not reference the AdventureGearAI database."
    Test-DocContains -Path $moduleReadme -Pattern ("Invoke-DemoModule\.ps1 -Modules {0}\b" -f $n) `
        -FailureMessage "$moduleName README does not run the unified runner with -Modules $n."
}

# ---------------------------------------------------------------------------
# 3) Teaching guide references the unified flow.
# ---------------------------------------------------------------------------
$teachingGuideChecks = @(
    @{ Pattern = 'AdventureGearAI'; Message = 'teaching-guide.md does not reference the AdventureGearAI database.' },
    @{ Pattern = 'Invoke-DemoModule\.ps1'; Message = 'teaching-guide.md does not reference the unified module runner.' },
    @{ Pattern = 'Invoke-Bootstrap\.ps1'; Message = 'teaching-guide.md does not reference the bootstrap.' },
    @{ Pattern = 'ops\.DemoModuleState'; Message = 'teaching-guide.md does not reference ops.DemoModuleState.' },
    @{ Pattern = 'ops\.DemoEnvironment'; Message = 'teaching-guide.md does not reference ops.DemoEnvironment.' },
    @{ Pattern = 'Reset-AdventureGearAI\.ps1'; Message = 'teaching-guide.md does not reference the full reset wrapper.' },
    @{ Pattern = '(?i)module-scoped reset'; Message = 'teaching-guide.md does not describe module-scoped reset.' }
)
foreach ($check in $teachingGuideChecks) {
    Test-DocContains -Path $teachingGuide -Pattern $check.Pattern -FailureMessage $check.Message
}

# Each per-module section in the teaching guide must run the runner with its own
# module number.
foreach ($n in 1..11) {
    Test-DocContains -Path $teachingGuide -Pattern ("Invoke-DemoModule\.ps1 -Modules {0}\b" -f $n) `
        -FailureMessage ("teaching-guide.md does not run the runner with -Modules {0} for module M{0:d2}." -f $n)
}

# ---------------------------------------------------------------------------
# 4) Legacy prose allowance across every demo/doc surface (READMEs excluding the
#    tests folder, the teaching guide, and the demo-environment reference).
# ---------------------------------------------------------------------------
$proseFiles = [System.Collections.Generic.List[string]]::new()
foreach ($readme in (Get-ChildItem -Path $demoRoot -Recurse -File -Filter 'README.md' -ErrorAction SilentlyContinue)) {
    if ($readme.FullName.StartsWith($testsRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    $proseFiles.Add($readme.FullName)
}
if (Test-Path -LiteralPath $teachingGuide -PathType Leaf) { $proseFiles.Add($teachingGuide) }
if (Test-Path -LiteralPath $demoEnvironment -PathType Leaf) { $proseFiles.Add($demoEnvironment) }

foreach ($file in $proseFiles) {
    Test-LegacyProseAllowance -Path $file
}

# ---------------------------------------------------------------------------
# Result.
# ---------------------------------------------------------------------------
if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'PASS (all unified demo documentation checks succeeded)' -ForegroundColor Green
exit 0
