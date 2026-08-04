[CmdletBinding()]
param()

# ---------------------------------------------------------------------------
# Static analysis and repository-hygiene checks for the unified AdventureGearAI
# demo. This test needs no database. It verifies:
#   * every PowerShell asset under DEMO parses (AST, zero parser errors);
#   * every JSON asset under DEMO parses;
#   * the M07 SDK-style SQL project builds with zero errors (skipped only when
#     the dotnet SDK is genuinely unavailable - an external optional tool);
#   * no secrets, credentials, or unexpected GUIDs are committed under DEMO;
#   * no generated build outputs (bin/obj/dacpac/dll) are tracked by git;
#   * git diff --check is clean (no whitespace errors or conflict markers).
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

function Resolve-RepoPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($repoRoot.Length).TrimStart('\')
    }
    return $full
}

# Enumerate demo files by extension, excluding generated bin/obj trees.
function Get-DemoFiles {
    param([string[]]$Extensions)
    Get-ChildItem -LiteralPath $demoRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '\\(bin|obj)\\' -and
        ($Extensions -contains $_.Extension.ToLowerInvariant())
    }
}

Write-Host 'Unified demo static analysis and hygiene checks'
Write-Host ''

# --- 1. PowerShell AST parse ------------------------------------------------
$psFiles = @(Get-DemoFiles -Extensions '.ps1', '.psm1')
foreach ($file in $psFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $first = $parseErrors[0]
        Add-Failure "PowerShell parse error in $(Resolve-RepoPath $file.FullName): $($first.Message) (line $($first.Extent.StartLineNumber))."
    }
}
Write-Host "Parsed $($psFiles.Count) PowerShell file(s)."

# --- 2. JSON parse ----------------------------------------------------------
$jsonFiles = @(Get-DemoFiles -Extensions '.json')
foreach ($file in $jsonFiles) {
    try {
        $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    }
    catch {
        Add-Failure "JSON parse error in $(Resolve-RepoPath $file.FullName): $($_.Exception.Message)"
    }
}
Write-Host "Parsed $($jsonFiles.Count) JSON file(s)."

# --- 3. M07 SDK-style SQL project build -------------------------------------
$sqlProject = Join-Path $demoRoot 'M07\common\Dp800.Database\Dp800.Database.sqlproj'
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Write-Host 'SKIP: dotnet SDK not available; M07 SQL project build not exercised.' -ForegroundColor Yellow
}
elseif (-not (Test-Path -LiteralPath $sqlProject -PathType Leaf)) {
    Add-Failure "M07 SQL project not found at $(Resolve-RepoPath $sqlProject)."
}
else {
    $buildOutput = & $dotnet.Source build $sqlProject -v minimal --nologo 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "M07 SQL project build failed (exit $LASTEXITCODE):`n$buildOutput"
    }
    elseif ($buildOutput -match '(?im)^\s*\d+\s+Error\(s\)' -and $buildOutput -notmatch '(?im)^\s*0\s+Error\(s\)') {
        Add-Failure "M07 SQL project build reported errors:`n$buildOutput"
    }
    else {
        Write-Host 'M07 SQL project built with 0 errors.'
    }
}

# --- 4. Secret / GUID scan --------------------------------------------------
# The needle for the plaintext-secure-string anti-pattern is split so this
# scanner does not match its own source text.
$plainTextNeedle = '(?i)-AsPlain' + 'Text'
$secretPatterns = @(
    @{ Name = 'Private key block';        Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' }
    @{ Name = 'GitHub token';             Pattern = 'gh[pousr]_[A-Za-z0-9]{20,}' }
    @{ Name = 'GitHub fine-grained PAT';  Pattern = 'github_pat_[A-Za-z0-9_]{20,}' }
    @{ Name = 'Slack token';              Pattern = 'xox[baprs]-[A-Za-z0-9-]{10,}' }
    @{ Name = 'AWS access key id';        Pattern = 'AKIA[0-9A-Z]{16}' }
    @{ Name = 'Google API key';           Pattern = 'AIza[0-9A-Za-z_\-]{35}' }
    @{ Name = 'OpenAI-style secret key';  Pattern = 'sk-[A-Za-z0-9]{20,}' }
    @{ Name = 'JWT';                      Pattern = 'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{6,}' }
    @{ Name = 'Plaintext secure string';  Pattern = $plainTextNeedle }
)
$guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$allowedGuid = '00000000-0000-0000-0000-000000000000'
$credentialAssignment = '(?i)\b(?:password|pwd)\s*=\s*["'']?([^\s;"''<>]{6,})'

$textExtensions = '.ps1', '.psm1', '.sql', '.json', '.md', '.xml', '.yml', '.yaml', '.sqlproj', '.txt', '.config'
$scanFiles = @(Get-DemoFiles -Extensions $textExtensions)
foreach ($file in $scanFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ([string]::IsNullOrEmpty($content)) { continue }
    $rel = Resolve-RepoPath $file.FullName

    foreach ($pattern in $secretPatterns) {
        if ([regex]::IsMatch($content, $pattern.Pattern)) {
            Add-Failure "Potential secret ($($pattern.Name)) committed in $rel."
        }
    }

    foreach ($match in [regex]::Matches($content, $credentialAssignment)) {
        $value = $match.Groups[1].Value
        if ($value -match '^\$' -or $value -match '^@' -or
            $value -match '(?i)^(true|false)$' -or $value -match '(?i)replace|env\(' -or
            $value -match '^\[Environment\]::GetEnvironmentVariable\(') {
            continue
        }
        Add-Failure "Potential hardcoded credential in ${rel}: '$($match.Value.Trim())'."
    }

    foreach ($match in [regex]::Matches($content, $guidPattern)) {
        if ($match.Value -ieq $allowedGuid) { continue }
        Add-Failure "Unexpected GUID committed in ${rel}: $($match.Value)."
    }
}
Write-Host "Scanned $($scanFiles.Count) text file(s) for secrets and GUIDs."

# --- 5. No generated build outputs are tracked ------------------------------
$trackedDemo = @(& git -C $repoRoot ls-files -- DEMO 2>$null)
$trackedArtifacts = @($trackedDemo | Where-Object {
    $_ -match '/(bin|obj)/' -or $_ -match '\.(dacpac|dll|exe|pdb)$'
})
if ($trackedArtifacts.Count -gt 0) {
    Add-Failure "Generated build artifacts are tracked by git: $($trackedArtifacts -join ', ')."
}
Write-Host "Checked $($trackedDemo.Count) git-tracked DEMO path(s) for stray build outputs."

# --- 6. git diff --check (whitespace / conflict markers) --------------------
$diffCheck = & git -C $repoRoot diff --check 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($diffCheck)) {
    Add-Failure "git diff --check reported issues: $($diffCheck.Trim())"
}
$diffCachedCheck = & git -C $repoRoot diff --cached --check 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($diffCachedCheck)) {
    Add-Failure "git diff --cached --check reported issues: $($diffCachedCheck.Trim())"
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all unified demo static analysis and hygiene checks succeeded)' -ForegroundColor Green
exit 0
