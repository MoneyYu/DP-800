[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$testsRoot = Join-Path $demoRoot 'tests'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

function ConvertTo-CanonicalRunnablePowerShellCommand {
    param([string]$Command)

    $trimmedCommand = $Command.Trim()
    if ($trimmedCommand -notmatch '^(?i:&\s+)?(?i:pwsh(?:\.exe)?)\s+(?<noProfile>(?i:-NoProfile)\s+)?(?i:-File)(?<fileAndArguments>\s+.+)$') {
        return $null
    }

    $noProfile = if ($Matches['noProfile']) { ' -NoProfile' } else { '' }
    return "pwsh$noProfile -File $($Matches['fileAndArguments'].Trim())"
}

function Test-ExplicitDatabaseSafety {
    param([string]$Command)

    $canonicalCommand = ConvertTo-CanonicalRunnablePowerShellCommand -Command $Command
    if ($null -ne $canonicalCommand) {
        $Command = $canonicalCommand
    }

    $fullDatabaseParameterName = '(?i:Database)'
    $abbreviatedDatabaseParameterName = '(?i:Databas|Databa|Datab|Data|Dat|Da|D)'
    $databaseParameterName = '(?i:Database|Databas|Databa|Datab|Data|Dat|Da|D)'
    $databaseParameters = @([regex]::Matches($Command, "(?<!\S)-$fullDatabaseParameterName(?=[:\s]|$)"))
    if ([regex]::IsMatch($Command, '(?i)(?<!\S)-File\s+DEMO/scripts/Invoke-Dp800Sql\.ps1(?=\s|$)')) {
        $databaseParameters += [regex]::Matches($Command, "(?<!\S)-$abbreviatedDatabaseParameterName(?=[:\s]|$)")
    }
    $validDatabaseTarget = "\A-$databaseParameterName(?::(?:AdventureGearAI|'AdventureGearAI'|`"AdventureGearAI`")(?=\s|`$)|\s+(?:AdventureGearAI|'AdventureGearAI'|`"AdventureGearAI`")(?=\s|`$))"
    foreach ($databaseParameter in $databaseParameters) {
        if (-not [regex]::IsMatch($Command.Substring($databaseParameter.Index), $validDatabaseTarget)) {
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
        if ($state -eq 'DoubleQuote') {
            if ($character -eq '"' -and $next -eq '"') {
                $index++
            }
            elseif ($character -eq '"') {
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
        elseif ($character -eq '"') {
            $state = 'DoubleQuote'
        }
        elseif ($character -eq '[') {
            $state = 'BracketIdentifier'
        }
    }
    return $commentMask
}

function Get-UnicodeCodePointAt {
    param(
        [string]$Text,
        [int]$Index
    )

    $codeUnit = [int][char]$Text[$Index]
    if ([char]::IsHighSurrogate($Text[$Index]) -and
        $Index + 1 -lt $Text.Length -and
        [char]::IsLowSurrogate($Text[$Index + 1])) {
        return 0x10000 + (($codeUnit - 0xD800) * 0x400) + ([int][char]$Text[$Index + 1] - 0xDC00)
    }
    return $codeUnit
}

function Get-UnicodeCodePointLengthAt {
    param(
        [string]$Text,
        [int]$Index
    )

    if ([char]::IsHighSurrogate($Text[$Index]) -and
        $Index + 1 -lt $Text.Length -and
        [char]::IsLowSurrogate($Text[$Index + 1])) {
        return 2
    }
    return 1
}

function Test-IntendedHanCodePoint {
    param([uint32]$CodePoint)

    return ($CodePoint -ge 0x3400 -and $CodePoint -le 0x4DBF) -or
        ($CodePoint -ge 0x4E00 -and $CodePoint -le 0x9FFF) -or
        ($CodePoint -ge 0xF900 -and $CodePoint -le 0xFAFF) -or
        ($CodePoint -ge 0x20000 -and $CodePoint -le 0x2A6DF) -or
        ($CodePoint -ge 0x2A700 -and $CodePoint -le 0x2B73F) -or
        ($CodePoint -ge 0x2B740 -and $CodePoint -le 0x2B81F) -or
        ($CodePoint -ge 0x2B820 -and $CodePoint -le 0x2CEAF) -or
        ($CodePoint -ge 0x2CEB0 -and $CodePoint -le 0x2EBEF) -or
        ($CodePoint -ge 0x2EBF0 -and $CodePoint -le 0x2EE5D) -or
        ($CodePoint -ge 0x2F800 -and $CodePoint -le 0x2FA1F) -or
        ($CodePoint -ge 0x30000 -and $CodePoint -le 0x3134A) -or
        ($CodePoint -ge 0x31350 -and $CodePoint -le 0x323AF) -or
        ($CodePoint -ge 0x323B0 -and $CodePoint -le 0x33479)
}

function Test-TextContainsIntendedHan {
    param([string]$Text)

    for ($index = 0; $index -lt $Text.Length; $index += Get-UnicodeCodePointLengthAt -Text $Text -Index $index) {
        if (Test-IntendedHanCodePoint -CodePoint (Get-UnicodeCodePointAt -Text $Text -Index $index)) {
            return $true
        }
    }
    return $false
}

function Test-SqlTextAllowsHanOnlyInComments {
    param([string]$Text)

    $commentMask = Get-SqlCommentMask -Text $Text
    for ($index = 0; $index -lt $Text.Length; $index += Get-UnicodeCodePointLengthAt -Text $Text -Index $index) {
        if ((Test-IntendedHanCodePoint -CodePoint (Get-UnicodeCodePointAt -Text $Text -Index $index)) -and
            -not $commentMask[$index]) {
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
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database ''AdventureGearAI'''; Expected = $true; Name = 'space single-quoted AdventureGearAI target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database "AdventureGearAI"'; Expected = $true; Name = 'space double-quoted AdventureGearAI target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:''AdventureGearAI'''; Expected = $true; Name = 'colon single-quoted AdventureGearAI target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:"AdventureGearAI"'; Expected = $true; Name = 'colon double-quoted AdventureGearAI target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database master'; Expected = $false; Name = 'space master target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:master'; Expected = $false; Name = 'colon master target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database: AdventureGearAI'; Expected = $false; Name = 'colon whitespace target' }
        [pscustomobject]@{ Command = "pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:'''AdventureGearAI'"; Expected = $false; Name = 'colon single-quoted token prefix target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:''AdventureGearAI'''''''; Expected = $false; Name = 'colon single-quoted token suffix target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:"AdventureGearAI"foo'; Expected = $false; Name = 'colon quoted token suffix target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database AdventureGearAIFoo'; Expected = $false; Name = 'unquoted token suffix target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database $database'; Expected = $false; Name = 'variable database target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database $(Get-Database)'; Expected = $false; Name = 'expression database target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master'; Expected = $false; Name = 'database single-letter abbreviation master target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Dat master'; Expected = $false; Name = 'database partial abbreviation master target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Unrelated.ps1 -D master'; Expected = $true; Name = 'unrelated script single-letter argument is not a database target' }
        [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database adventuregearai'; Expected = $false; Name = 'lowercase AdventureGearAI target' }
    )) {
    if ((Test-ExplicitDatabaseSafety -Command $fixture.Command) -ne $fixture.Expected) {
        Add-Failure "Database safety fixture failed for $($fixture.Name)."
    }
}

foreach ($fixture in @(
        [pscustomobject]@{ Text = '/* outer /* nested */ 繁中 */'; Expected = $true; Name = 'nested block comment Han text' }
        [pscustomobject]@{ Text = 'SELECT N''繁中'';'; Expected = $false; Name = 'string literal Han text' }
        [pscustomobject]@{ Text = 'SELECT [繁中];'; Expected = $false; Name = 'bracket identifier Han text' }
        [pscustomobject]@{ Text = 'SELECT "-- 繁中";'; Expected = $false; Name = 'double-quoted identifier Han text' }
        [pscustomobject]@{ Text = 'SELECT "a""b"; -- 繁中'; Expected = $true; Name = 'escaped double-quoted identifier followed by comment Han text' }
        [pscustomobject]@{ Text = 'SELECT "a""--""b"; 繁中;'; Expected = $false; Name = 'escaped double-quoted identifier does not mask later executable Han text' }
        [pscustomobject]@{ Text = 'SELECT 繁中;'; Expected = $false; Name = 'executable Han text' }
        [pscustomobject]@{ Text = 'SELECT 㐀;'; Expected = $false; Name = 'executable Extension A Han text' }
        [pscustomobject]@{ Text = 'SELECT 豈;'; Expected = $false; Name = 'executable CJK compatibility Han text' }
        [pscustomobject]@{ Text = "SELECT $([char]::ConvertFromUtf32(0x20000));"; Expected = $false; Name = 'executable supplementary Han text' }
        [pscustomobject]@{ Text = '-- 㐀'; Expected = $true; Name = 'Extension A Han comment text' }
        [pscustomobject]@{ Text = '-- 豈'; Expected = $true; Name = 'CJK compatibility Han comment text' }
        [pscustomobject]@{ Text = "-- $([char]::ConvertFromUtf32(0x20000))"; Expected = $true; Name = 'supplementary Han comment text' }
    )) {
    if ((Test-SqlTextAllowsHanOnlyInComments -Text $fixture.Text) -ne $fixture.Expected) {
        Add-Failure "SQL lexical fixture failed for $($fixture.Name)."
    }
}

foreach ($range in @(
        [pscustomobject]@{ Name = 'Extension I'; Start = 0x2EBF0; End = 0x2EE5D }
        [pscustomobject]@{ Name = 'Compatibility Ideographs Supplement'; Start = 0x2F800; End = 0x2FA1F }
        [pscustomobject]@{ Name = 'Extension G'; Start = 0x30000; End = 0x3134A }
        [pscustomobject]@{ Name = 'Extension H'; Start = 0x31350; End = 0x323AF }
        [pscustomobject]@{ Name = 'Extension J'; Start = 0x323B0; End = 0x33479 }
    )) {
    if (-not (Test-IntendedHanCodePoint -CodePoint $range.Start) -or
        -not (Test-IntendedHanCodePoint -CodePoint $range.End)) {
        Add-Failure "$($range.Name) Han range boundary is not recognized."
    }

    $han = [char]::ConvertFromUtf32($range.End)
    foreach ($fixture in @(
            [pscustomobject]@{ Text = "SELECT $han;"; Expected = $false; Name = "$($range.Name) executable Han text" }
            [pscustomobject]@{ Text = "SELECT N'$han';"; Expected = $false; Name = "$($range.Name) string Han text" }
            [pscustomobject]@{ Text = "-- $han"; Expected = $true; Name = "$($range.Name) Han comment text" }
        )) {
        if ((Test-SqlTextAllowsHanOnlyInComments -Text $fixture.Text) -ne $fixture.Expected) {
            Add-Failure "SQL lexical fixture failed for $($fixture.Name)."
        }
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
    $normalizedText = $Text -replace '[ \t]*`\r?\n[ \t]*', ' '
    foreach ($line in ($normalizedText -split "`r?`n")) {
        $command = ConvertTo-CanonicalRunnablePowerShellCommand -Command $line
        if ($null -ne $command) {
            [void]$commands.Add($command)
        }
    }
    return $commands
}

if (@(Get-RunnablePowerShellCommands -Text '# pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database:master').Count -ne 0) {
    Add-Failure 'Command extraction fixture incorrectly treats a comment as runnable.'
}
if (@(Get-RunnablePowerShellCommands -Text @'
```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database 'AdventureGearAI'
```
'@).Count -ne 1) {
    Add-Failure 'Command extraction fixture does not recognize a standard code-block command.'
}
if (@(Get-RunnablePowerShellCommands -Text @'
```powershell
# pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Database AdventureGearAI
```
'@).Count -ne 0) {
    Add-Failure 'Command extraction fixture incorrectly treats a commented code-block command as runnable.'
}
$standardWrapperVariants = @(
    [pscustomobject]@{ Command = 'pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master'; Name = 'pwsh' }
    [pscustomobject]@{ Command = 'pwsh.exe -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master'; Name = 'pwsh.exe' }
    [pscustomobject]@{ Command = '& pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master'; Name = 'call operator pwsh' }
    [pscustomobject]@{ Command = '& pwsh.exe -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master'; Name = 'call operator pwsh.exe' }
)
foreach ($fixture in $standardWrapperVariants) {
    $commands = @(Get-RunnablePowerShellCommands -Text $fixture.Command)
    if ($commands.Count -ne 1 -or
        $commands[0] -cne 'pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master') {
        Add-Failure "Command extraction fixture does not normalize the $($fixture.Name) wrapper."
    }
    if (Test-ExplicitDatabaseSafety -Command $fixture.Command) {
        Add-Failure "Database safety fixture does not reject a master target through the $($fixture.Name) wrapper."
    }
}
$noProfileWrapperCommand = 'pwsh -File DEMO/scripts/Invoke-Dp800Sql.ps1 -D master'
$noProfileWrapperCommands = @(Get-RunnablePowerShellCommands -Text $noProfileWrapperCommand)
if ($noProfileWrapperCommands.Count -ne 1 -or
    $noProfileWrapperCommands[0] -cne $noProfileWrapperCommand) {
    Add-Failure 'Command extraction fixture does not preserve an explicit profile-loading wrapper.'
}
if (Test-ExplicitDatabaseSafety -Command $noProfileWrapperCommand) {
    Add-Failure 'Database safety fixture does not reject a master target through a profile-loading wrapper.'
}
$masterContinuationCommands = @(Get-RunnablePowerShellCommands -Text @'
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 `
    -InputFile DEMO/M01/01-Create-Database.sql `
    -Database master
'@)
if ($masterContinuationCommands.Count -ne 1 -or
    (Test-ExplicitDatabaseSafety -Command $masterContinuationCommands[0])) {
    Add-Failure 'Command extraction fixture does not reject a master target on a backtick continuation.'
}
$validContinuationCommands = @(Get-RunnablePowerShellCommands -Text @'
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 `
    -InputFile DEMO/M01/01-Create-Database.sql `
    -Database AdventureGearAI
'@)
$expectedValidContinuationCommand = 'pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -InputFile DEMO/M01/01-Create-Database.sql -Database AdventureGearAI'
if ($validContinuationCommands.Count -ne 1 -or
    $validContinuationCommands[0] -cne $expectedValidContinuationCommand -or
    -not (Test-ExplicitDatabaseSafety -Command $validContinuationCommands[0])) {
    Add-Failure 'Command extraction fixture does not deterministically normalize a valid backtick continuation.'
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
        if ($command -notmatch '(?i)^pwsh(?: -NoProfile)? -File\s+DEMO/[^\s]+\.ps1(?:\s|$)') {
            Add-Failure "$englishRelativePath has a runnable command without an explicit DEMO script path: $command"
        }
    }
    foreach ($command in $localizedCommands) {
        if ($command -notmatch '(?i)^pwsh(?: -NoProfile)? -File\s+DEMO/[^\s]+\.ps1(?:\s|$)') {
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

foreach ($fixture in $standardWrapperVariants) {
    $adventureGearCommand = $fixture.Command -replace '(?i)-D master$', '-Database AdventureGearAI'
    Test-CommandSet -EnglishPath 'English fixture' -LocalizedPath "$($fixture.Name) fixture" `
        -EnglishText @'
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -InputFile DEMO/M01/01-Create-Database.sql
'@ `
        -LocalizedText "$adventureGearCommand`npwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -InputFile DEMO/M01/01-Create-Database.sql"
}
Test-CommandSet -EnglishPath 'profile-loading English fixture' -LocalizedPath 'profile-loading zh-TW fixture' `
    -EnglishText @'
pwsh -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI
pwsh -File DEMO/scripts/Invoke-Dp800Sql.ps1 -InputFile DEMO/M01/01-Create-Database.sql
'@ `
    -LocalizedText @'
& pwsh.exe -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI
& pwsh.exe -File DEMO/scripts/Invoke-Dp800Sql.ps1 -InputFile DEMO/M01/01-Create-Database.sql
'@

function Test-SqlHanUsage {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.IO.File]::ReadAllText($Path)
    if (-not (Test-TextContainsIntendedHan -Text $text)) { return }

    $relativePath = Resolve-RepoPath $Path
    $hasUtf8Bom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasUtf8Bom) {
        Add-Failure "$relativePath contains Han characters but is not encoded as UTF-8 with a BOM."
    }

    $commentMask = Get-SqlCommentMask -Text $text

    for ($index = 0; $index -lt $text.Length; $index += Get-UnicodeCodePointLengthAt -Text $text -Index $index) {
        if ((Test-IntendedHanCodePoint -CodePoint (Get-UnicodeCodePointAt -Text $text -Index $index)) -and
            -not $commentMask[$index]) {
            Add-Failure "$relativePath contains Han characters outside a SQL comment."
            break
        }
    }
}

function Test-EnglishLanguageSwitch {
    param(
        [string]$Path,
        [string]$Text
    )

    $lines = $Text -split "`r?`n"
    $firstMeaningfulIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if (-not [string]::IsNullOrWhiteSpace($lines[$index])) {
            $firstMeaningfulIndex = $index
            break
        }
    }

    if ($firstMeaningfulIndex -lt 0) {
        Add-Failure "$(Resolve-RepoPath $Path) is empty and cannot contain a language-switch link."
        return
    }

    $languageSwitchIndex = $firstMeaningfulIndex
    if ($lines[$firstMeaningfulIndex] -match '^#\s+') {
        $languageSwitchIndex++
        while ($languageSwitchIndex -lt $lines.Count -and
            [string]::IsNullOrWhiteSpace($lines[$languageSwitchIndex])) {
            $languageSwitchIndex++
        }
    }

    $expectedLanguageSwitch = 'English | [繁體中文](README.zh-TW.md)'
    if ($languageSwitchIndex -ge $lines.Count -or
        $lines[$languageSwitchIndex] -cne $expectedLanguageSwitch) {
        Add-Failure "$(Resolve-RepoPath $Path) must place '$expectedLanguageSwitch' after its H1 heading or as its first meaningful content."
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
        if ($command -notmatch '(?i)^pwsh(?: -NoProfile)? -File\s+DEMO/[^\s]+\.ps1(?:\s|$)') {
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
    $englishText = Get-DocumentText -Path $englishReadme.FullName
    if ($null -eq $englishText) { continue }
    Test-EnglishLanguageSwitch -Path $englishReadme.FullName -Text $englishText

    if (-not (Test-Path -LiteralPath $localizedPath -PathType Leaf)) {
        Add-Failure "Missing Traditional Chinese sibling for ${englishRelativePath}: $(Resolve-RepoPath $localizedPath)"
        continue
    }

    $localizedText = Get-DocumentText -Path $localizedPath
    if ($null -eq $localizedText) { continue }

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
