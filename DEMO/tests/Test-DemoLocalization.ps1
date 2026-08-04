[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$testsRoot = Join-Path $demoRoot 'tests'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

function Test-ExplicitDatabaseSafety {
    param([string]$Command)

    $databaseArguments = [regex]::Matches(
        $Command,
        '(?i)(?<!\S)-Database(?::\s*|\s+)(?<value>"[^"]*"|''[^'']*''|\S+)')
    foreach ($databaseArgument in $databaseArguments) {
        $databaseName = $databaseArgument.Groups['value'].Value.Trim([char[]]@('"', "'"))
        if (-not $databaseName.Equals('AdventureGearAI', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Get-SqlCommentMask {
    param([string]$Text)

    $commentMask = [bool[]]::new($Text.Length)
    $state = 'Normal'
    $blockCommentDepth = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }

        if ($state -eq 'LineComment') {
            if ($character -eq "`r" -or $character -eq "`n") {
                $state = 'Normal'
            }
            else {
                $commentMask[$index] = $true
            }
            continue
        }
        if ($state -eq 'BlockComment') {
            $commentMask[$index] = $true
            if ($character -eq '/' -and $next -eq '*') {
                $commentMask[$index + 1] = $true
                $index++
                $blockCommentDepth++
            }
            elseif ($character -eq '*' -and $next -eq '/') {
                $commentMask[$index + 1] = $true
                $index++
                $blockCommentDepth--
                if ($blockCommentDepth -eq 0) {
                    $state = 'Normal'
                }
            }
            continue
        }
        if ($state -eq 'SingleQuote') {
            if ($character -eq "'" -and $next -eq "'") {
                $index++
            }
            elseif ($character -eq "'") {
                $state = 'Normal'
            }
            continue
        }
        if ($state -eq 'BracketIdentifier') {
            if ($character -eq ']' -and $next -eq ']') {
                $index++
            }
            elseif ($character -eq ']') {
                $state = 'Normal'
            }
            continue
        }

        if ($character -eq '-' -and $next -eq '-') {
            $commentMask[$index] = $true
            $commentMask[$index + 1] = $true
            $index++
            $state = 'LineComment'
        }
        elseif ($character -eq '/' -and $next -eq '*') {
            $commentMask[$index] = $true
            $commentMask[$index + 1] = $true
            $index++
            $blockCommentDepth = 1
            $state = 'BlockComment'
        }
        elseif ($character -eq "'") {
            $state = 'SingleQuote'
        }
        elseif ($character -eq '[') {
            $state = 'BracketIdentifier'
        }
    }
    return $commentMask
}

function Test-SqlTextAllowsHanOnlyInComments {
    param([string]$Text)

    $commentMask = Get-SqlCommentMask -Text $Text
    for ($index = 0; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -match '[\p{IsCJKUnifiedIdeographs}]' -and -not $commentMask[$index]) {
            return $false
        }
    }
    return $true
}

function Test-PathIsDirectoryOrDescendant {
    param(
        [string]$Path,
        [string]$Directory
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    $normalizedDirectory = [System.IO.Path]::GetFullPath($Directory).TrimEnd([char[]]@('\', '/'))
    return $normalizedPath.Equals($normalizedDirectory, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith(
            $normalizedDirectory + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)
}

foreach ($fixture in @(
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database AdventureGearAI'; Expected = $true; Name = 'space AdventureGearAI target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:AdventureGearAI'; Expected = $true; Name = 'colon AdventureGearAI target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database master'; Expected = $false; Name = 'space master target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:master'; Expected = $false; Name = 'colon master target' }
    )) {
    if ((Test-ExplicitDatabaseSafety -Command $fixture.Command) -ne $fixture.Expected) {
        Add-Failure "Database safety fixture failed for $($fixture.Name)."
    }
}

foreach ($fixture in @(
        [pscustomobject]@{ Text = '/* outer /* nested */ 繁中 */'; Expected = $true; Name = 'nested block comment Han text' }
        [pscustomobject]@{ Text = 'SELECT N''繁中'';'; Expected = $false; Name = 'string literal Han text' }
        [pscustomobject]@{ Text = 'SELECT [繁中];'; Expected = $false; Name = 'bracket identifier Han text' }
        [pscustomobject]@{ Text = 'SELECT 繁中;'; Expected = $false; Name = 'executable Han text' }
    )) {
    if ((Test-SqlTextAllowsHanOnlyInComments -Text $fixture.Text) -ne $fixture.Expected) {
        Add-Failure "SQL lexical fixture failed for $($fixture.Name)."
    }
}

if (Test-PathIsDirectoryOrDescendant -Path (Join-Path $demoRoot 'testsArchive\README.md') -Directory $testsRoot) {
    Add-Failure 'README discovery fixture incorrectly excludes DEMO\testsArchive.'
}
if (-not (Test-PathIsDirectoryOrDescendant -Path (Join-Path $testsRoot 'fixtures\README.md') -Directory $testsRoot)) {
    Add-Failure 'README discovery fixture does not exclude a true DEMO\tests descendant.'
}

function Resolve-RepoPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($repoRoot.Length).TrimStart('\')
    }
    return $full
}

function Get-DocumentText {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllText($Path)
    }
    catch {
        Add-Failure "Could not read $(Resolve-RepoPath $Path): $($_.Exception.Message)"
        return $null
    }
}

function Get-RunnablePowerShellCommands {
    param([string]$Text)

    $commands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in ($Text -split "`r?`n")) {
        $command = $line.Trim()
        if ($command -match '(?i)^pwsh -NoProfile -File\s+') {
            [void]$commands.Add($command)
        }
    }
    return $commands
}

if (@(Get-RunnablePowerShellCommands -Text '# pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:master').Count -ne 0) {
    Add-Failure 'Command extraction fixture incorrectly treats a comment as runnable.'
}

function Test-ByteArraysEqual {
    param([byte[]]$Left, [byte[]]$Right)

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Test-CommandSet {
    param(
        [string]$EnglishPath,
        [string]$LocalizedPath,
        [string]$EnglishText,
        [string]$LocalizedText
    )

    $englishCommands = Get-RunnablePowerShellCommands -Text $EnglishText
    $localizedCommands = Get-RunnablePowerShellCommands -Text $LocalizedText
    $englishRelativePath = Resolve-RepoPath $EnglishPath
    $localizedRelativePath = Resolve-RepoPath $LocalizedPath

    if ($englishCommands.Count -eq 0) {
        Add-Failure "$englishRelativePath has no runnable 'pwsh -NoProfile -File' command lines to localize."
    }

    foreach ($command in $englishCommands) {
        if ($command -notmatch '(?i)^pwsh -NoProfile -File\s+DEMO/[^\s]+\.ps1(?:\s|$)') {
            Add-Failure "$englishRelativePath has a runnable command without an explicit DEMO script path: $command"
        }
    }
    foreach ($command in $localizedCommands) {
        if ($command -notmatch '(?i)^pwsh -NoProfile -File\s+DEMO/[^\s]+\.ps1(?:\s|$)') {
            Add-Failure "$localizedRelativePath has a runnable command without an explicit DEMO script path: $command"
        }
        if ($command -match '(?i)DP800_M\d{2}') {
            Add-Failure "$localizedRelativePath has a runnable command targeting a legacy DP800_Mxx database: $command"
        }
        if (-not (Test-ExplicitDatabaseSafety -Command $command)) {
            Add-Failure "$localizedRelativePath has a non-AdventureGearAI database target: $command"
        }
    }

    foreach ($command in $englishCommands) {
        if (-not $localizedCommands.Contains($command)) {
            Add-Failure "$localizedRelativePath is missing the exact runnable command from ${englishRelativePath}: $command"
        }
    }
    foreach ($command in $localizedCommands) {
        if (-not $englishCommands.Contains($command)) {
            Add-Failure "$localizedRelativePath has a runnable command not present in ${englishRelativePath}: $command"
        }
    }
}

function Test-SqlHanUsage {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text -notmatch '[\p{IsCJKUnifiedIdeographs}]') { return }

    $relativePath = Resolve-RepoPath $Path
    $hasUtf8Bom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasUtf8Bom) {
        Add-Failure "$relativePath contains Han characters but is not encoded as UTF-8 with a BOM."
    }

    $commentMask = Get-SqlCommentMask -Text $text

    for ($index = 0; $index -lt $text.Length; $index++) {
        if ($text[$index] -match '[\p{IsCJKUnifiedIdeographs}]' -and -not $commentMask[$index]) {
            Add-Failure "$relativePath contains Han characters outside a SQL comment."
            break
        }
    }
}

Write-Host 'Traditional Chinese demo localization regression harness'
Write-Host "Repository root: $repoRoot"
Write-Host ''

$englishReadmes = @(
    Get-ChildItem -LiteralPath $demoRoot -Recurse -File -Filter 'README.md' |
        Where-Object { -not (Test-PathIsDirectoryOrDescendant -Path $_.FullName -Directory $testsRoot) }
)
$localizedReadmes = @(
    Get-ChildItem -LiteralPath $demoRoot -Recurse -File -Filter 'README.zh-TW.md' |
        Where-Object { -not (Test-PathIsDirectoryOrDescendant -Path $_.FullName -Directory $testsRoot) }
)

$allEnglishCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($englishReadme in $englishReadmes) {
    $englishText = Get-DocumentText -Path $englishReadme.FullName
    if ($null -eq $englishText) { continue }
    foreach ($command in (Get-RunnablePowerShellCommands -Text $englishText)) {
        [void]$allEnglishCommands.Add($command)
        if ($command -notmatch '(?i)^pwsh -NoProfile -File\s+DEMO/[^\s]+\.ps1(?:\s|$)') {
            Add-Failure "$(Resolve-RepoPath $englishReadme.FullName) has a runnable command without an explicit DEMO script path: $command"
        }
    }
}
foreach ($requiredFragment in '-Modules', '-Force', '-Database', '-InputFile') {
    if (-not @($allEnglishCommands | Where-Object { $_.Contains($requiredFragment) }).Count) {
        Add-Failure "English demo command set does not include the required $requiredFragment argument."
    }
}
if (-not @($allEnglishCommands | Where-Object { $_ -match '(?i)-Database\s+AdventureGearAI(?:\s|$)' }).Count) {
    Add-Failure 'English demo command set does not include an AdventureGearAI database target.'
}

foreach ($englishReadme in $englishReadmes) {
    $localizedPath = Join-Path $englishReadme.DirectoryName 'README.zh-TW.md'
    $englishRelativePath = Resolve-RepoPath $englishReadme.FullName
    if (-not (Test-Path -LiteralPath $localizedPath -PathType Leaf)) {
        Add-Failure "Missing Traditional Chinese sibling for ${englishRelativePath}: $(Resolve-RepoPath $localizedPath)"
        continue
    }

    $localizedText = Get-DocumentText -Path $localizedPath
    $englishText = Get-DocumentText -Path $englishReadme.FullName
    if ($null -eq $englishText -or $null -eq $localizedText) { continue }

    if (-not $englishText.Contains('[繁體中文](README.zh-TW.md)')) {
        Add-Failure "$englishRelativePath is missing the required [繁體中文](README.zh-TW.md) language-switch link."
    }
    if (-not $localizedText.Contains('[English](README.md)')) {
        Add-Failure "$(Resolve-RepoPath $localizedPath) is missing the required [English](README.md) language-switch link."
    }
    if ($localizedText -notmatch '[\p{IsCJKUnifiedIdeographs}]') {
        Add-Failure "$(Resolve-RepoPath $localizedPath) contains no Han characters."
    }

    $englishBytes = [System.IO.File]::ReadAllBytes($englishReadme.FullName)
    $localizedBytes = [System.IO.File]::ReadAllBytes($localizedPath)
    if ($englishText -ceq $localizedText -or
        (Test-ByteArraysEqual -Left $englishBytes -Right $localizedBytes)) {
        Add-Failure "$(Resolve-RepoPath $localizedPath) must not be byte- or text-identical to $englishRelativePath."
    }

    Test-CommandSet -EnglishPath $englishReadme.FullName -LocalizedPath $localizedPath `
        -EnglishText $englishText -LocalizedText $localizedText
}

foreach ($localizedReadme in $localizedReadmes) {
    $englishPath = Join-Path $localizedReadme.DirectoryName 'README.md'
    if (-not (Test-Path -LiteralPath $englishPath -PathType Leaf)) {
        Add-Failure "Orphan Traditional Chinese README has no English sibling: $(Resolve-RepoPath $localizedReadme.FullName)"
    }

    $localizedText = Get-DocumentText -Path $localizedReadme.FullName
    if ($null -eq $localizedText) { continue }
    $lines = $localizedText -split "`r?`n"
    for ($lineNumber = 0; $lineNumber -lt $lines.Count; $lineNumber++) {
        $line = $lines[$lineNumber]
        if ($line -notmatch 'DP800_M\d{2}') { continue }

        if ($line -match '(?i)pwsh\s+-NoProfile\s+-File|\.ps1\b|-Database\b|-InputFile\b|Invoke-(Bootstrap|DemoModule|Dp800Sql)') {
            Add-Failure "$(Resolve-RepoPath $localizedReadme.FullName):$($lineNumber + 1) references DP800_Mxx on a runnable command line."
            continue
        }
        if ($line -notmatch '舊版|手動清理|不會自動刪除|絕不自動刪除') {
            Add-Failure "$(Resolve-RepoPath $localizedReadme.FullName):$($lineNumber + 1) mentions DP800_Mxx without explicit Traditional Chinese legacy cleanup framing."
        }
    }
}

foreach ($sqlFile in (Get-ChildItem -LiteralPath $demoRoot -Recurse -File -Filter '*.sql')) {
    Test-SqlHanUsage -Path $sqlFile.FullName
}

Write-Host "Discovered $($englishReadmes.Count) English README(s) and $($localizedReadmes.Count) Traditional Chinese README(s)."
if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all Traditional Chinese demo localization checks succeeded)' -ForegroundColor Green
exit 0
