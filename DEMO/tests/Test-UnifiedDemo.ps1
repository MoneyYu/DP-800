[CmdletBinding()]
param(
    [string]$BaseRef = 'HEAD~1',
    [string]$HeadRef = 'HEAD'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$bootstrapRoot = Join-Path $demoRoot 'bootstrap'
$moduleDirectories = Get-ChildItem -Path $demoRoot -Directory | Where-Object { $_.Name -match '^M\d{2}$' } | Sort-Object Name
$expectedBootstrapAssets = @(
    Join-Path $bootstrapRoot '00-create-adventuregear-database.sql'
    Join-Path $bootstrapRoot '01-initialize-adventuregear-demo.sql'
)
$expectedFullReset = Join-Path $demoRoot 'reset\Reset-AdventureGearAI.ps1'
$expectedDabObjects = @{
    Category = 'api.Categories'
    Product = 'api.Products'
    ProductCatalog = 'api.ProductCatalog'
}
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

function Resolve-RepoPath {
    param([string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if ($resolvedPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Substring($repoRoot.Length).TrimStart('\')
    }

    return $resolvedPath
}

function Get-FileText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing required file: $(Resolve-RepoPath -Path $Path)"
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Test-PatternPresent {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$FailureMessage
    )

    $text = Get-FileText -Path $Path
    if ($null -eq $text) {
        return
    }

    if ($text -notmatch $Pattern) {
        Add-Failure $FailureMessage
    }
}

function Test-PatternAbsent {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$FailureMessage
    )

    $text = Get-FileText -Path $Path
    if ($null -eq $text) {
        return
    }

    if ($text -match $Pattern) {
        Add-Failure $FailureMessage
    }
}

function Test-ReadmeExecutionTargets {
    param([string]$Path)

    $lines = Get-Content -LiteralPath $Path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -notmatch 'DP800_M\d{2}') {
            continue
        }

        $isExecutionTarget = $line -match '(?i)^\s*Run\b.*\bagainst\s+`?DP800_M\d{2}`?' -or
            $line -match '(?i)-Database\s+`?DP800_M\d{2}`?' -or
            $line -match '(?i)^\s*pwsh\b.*DP800_M\d{2}'

        if ($isExecutionTarget) {
            Add-Failure "Execution README $(Resolve-RepoPath -Path $Path):$($i + 1) still uses a DP800_Mxx execution target."
        }
    }
}

function Get-ChangedFilesInRange {
    param(
        [string]$Base,
        [string]$Head
    )

    $output = & git -C $repoRoot --no-pager diff --name-only $Base $Head -- 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Unable to determine changed files for git range '$Base..$Head': $($output -join ' ')"
        return @()
    }

    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-LineNumberFromIndex {
    param(
        [string]$Text,
        [int]$Index
    )

    if ([string]::IsNullOrEmpty($Text) -or $Index -le 0) {
        return 1
    }

    $safeLength = [Math]::Min($Index, $Text.Length)
    return ([regex]::Matches($Text.Substring(0, $safeLength), "\r?\n").Count + 1)
}

function Normalize-DatabaseTargetToken {
    param([string]$Target)

    return $Target.Trim().Trim('[', ']', '"', '''', '`', ';')
}

function Test-BootstrapScriptDatabaseTargets {
    param([string]$Path)

    $text = Get-FileText -Path $Path
    if ($null -eq $text) {
        return
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            Add-Failure "Bootstrap script $(Resolve-RepoPath -Path $Path):$($parseError.Extent.StartLineNumber) could not be parsed: $($parseError.Message)"
        }
        return
    }

    $allowedTargets = @('master', 'AdventureGearAI')
    $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($command in $commands) {
        $elements = @($command.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst] -or
                $element.ParameterName -ine 'Database') {
                continue
            }

            $argument = $element.Argument
            if ($null -eq $argument -and ($i + 1) -lt $elements.Count) {
                $argument = $elements[$i + 1]
            }

            $lineNumber = $element.Extent.StartLineNumber
            if ($null -eq $argument -or $argument -is [System.Management.Automation.Language.CommandParameterAst]) {
                Add-Failure "Bootstrap script $(Resolve-RepoPath -Path $Path):$lineNumber is missing a -Database target."
                continue
            }

            if ($argument -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                Add-Failure "Bootstrap script $(Resolve-RepoPath -Path $Path):$lineNumber database target must be the literal master or AdventureGearAI value. Found: $($argument.Extent.Text)"
                continue
            }

            $databaseTarget = $argument.Value
            if ($databaseTarget -notin $allowedTargets) {
                Add-Failure "Bootstrap script $(Resolve-RepoPath -Path $Path):$lineNumber uses a forbidden database target: $databaseTarget"
            }
        }
    }
}

function Test-BootstrapSqlScope {
    param([string]$Path)

    $text = Get-FileText -Path $Path
    if ($null -eq $text) {
        return
    }

    $legacyCommandPattern = '(?im)^\s*(?<Command>CREATE\s+DATABASE|ALTER\s+DATABASE|DROP\s+DATABASE(?:\s+IF\s+EXISTS)?|USE)\s+(?<Target>\[[^\]\r\n]+\]|"[^"\r\n]+"|''[^''\r\n]+''|[^\s;\r\n]+)'
    foreach ($match in [regex]::Matches($text, $legacyCommandPattern)) {
        $legacyTarget = Normalize-DatabaseTargetToken -Target $match.Groups['Target'].Value
        if ($legacyTarget -match '^DP800_M\d{2}$') {
            $lineNumber = Get-LineNumberFromIndex -Text $text -Index $match.Index
            Add-Failure "Bootstrap SQL asset $(Resolve-RepoPath -Path $Path):$lineNumber still targets legacy database $legacyTarget via $($match.Groups['Command'].Value.ToUpperInvariant())."
        }
    }

    $legacyDatabaseNameConstructionPattern = '(?im)^\s*(?:DECLARE|SET|SELECT)\s+(?<Variable>@\w*database\w*)\b[^\r\n]*DP800_M'
    foreach ($match in [regex]::Matches($text, $legacyDatabaseNameConstructionPattern)) {
        $lineNumber = Get-LineNumberFromIndex -Text $text -Index $match.Index
        Add-Failure "Bootstrap SQL asset $(Resolve-RepoPath -Path $Path):$lineNumber still constructs a legacy DP800_Mxx database name in $($match.Groups['Variable'].Value)."
    }

    $legacyDynamicSqlPattern = '(?im)^\s*(?:DECLARE|SET|SELECT)\s+(?<Variable>@\w*sql\w*)\b[^\r\n]*\b(?:CREATE|ALTER|DROP)\s+DATABASE\b[^\r\n]*DP800_M'
    foreach ($match in [regex]::Matches($text, $legacyDynamicSqlPattern)) {
        $lineNumber = Get-LineNumberFromIndex -Text $text -Index $match.Index
        Add-Failure "Bootstrap SQL asset $(Resolve-RepoPath -Path $Path):$lineNumber still builds a legacy DP800_Mxx database command in $($match.Groups['Variable'].Value)."
    }
}

function Test-FullResetScope {
    param([string]$Path)

    $fullResetText = Get-FileText -Path $Path
    if ($null -eq $fullResetText) {
        return
    }

    if ($fullResetText -notmatch 'AdventureGearAI') {
        Add-Failure 'Full reset script is not hard-scoped to AdventureGearAI.'
    }

    $destructiveTargetPattern = '(?im)^\s*(?<Command>ALTER\s+DATABASE|DROP\s+DATABASE(?:\s+IF\s+EXISTS)?)\s+(?<Target>\[[^\]\r\n]+\]|"[^"\r\n]+"|''[^''\r\n]+''|`[^`\r\n]+`|[^\s;\r\n]+)'
    foreach ($match in [regex]::Matches($fullResetText, $destructiveTargetPattern)) {
        $command = $match.Groups['Command'].Value.ToUpperInvariant()
        $rawTarget = $match.Groups['Target'].Value.Trim()
        $normalizedTarget = $rawTarget.Trim('[', ']', '"', '''', '`')

        if ($normalizedTarget -ne 'AdventureGearAI') {
            Add-Failure "Full reset script $command target must be the literal AdventureGearAI database. Found: $rawTarget"
        }
    }
}

Write-Host 'Unified demo regression harness'
Write-Host "Repository root: $repoRoot"
Write-Host "Git range: $BaseRef..$HeadRef"
Write-Host ''

$bootstrapScript = Join-Path $bootstrapRoot 'Invoke-Bootstrap.ps1'
Test-PatternAbsent -Path $bootstrapScript -Pattern '00-create-databases\.sql' -FailureMessage 'Bootstrap script still uses the legacy eleven-database create script.'
Test-PatternPresent -Path $bootstrapScript -Pattern '00-create-adventuregear-database\.sql' -FailureMessage 'Bootstrap script does not wire the AdventureGearAI create-database asset.'
Test-PatternPresent -Path $bootstrapScript -Pattern '01-initialize-adventuregear-demo\.sql' -FailureMessage 'Bootstrap script does not wire the AdventureGearAI initialization asset.'
Test-BootstrapScriptDatabaseTargets -Path $bootstrapScript

$bootstrapSqlFiles = @(Get-ChildItem -Path $bootstrapRoot -File -Filter '*.sql' -ErrorAction SilentlyContinue)
if ($bootstrapSqlFiles.Count -eq 0) {
    Add-Failure 'Bootstrap SQL assets are missing.'
}
else {
    foreach ($sqlFile in $bootstrapSqlFiles) {
        Test-BootstrapSqlScope -Path $sqlFile.FullName
    }
}

foreach ($asset in $expectedBootstrapAssets) {
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
        Add-Failure "Expected AdventureGearAI bootstrap asset is missing: $(Resolve-RepoPath -Path $asset)"
        continue
    }

    Test-PatternPresent -Path $asset -Pattern 'AdventureGearAI' -FailureMessage "AdventureGearAI bootstrap asset $(Resolve-RepoPath -Path $asset) does not mention AdventureGearAI."
}

$sqlFiles = @(Get-ChildItem -Path $demoRoot -Recurse -File -Include '*.sql' -ErrorAction SilentlyContinue)
$opsDefinitionsFound = @{
    'ops.DemoEnvironment' = $false
    'ops.DemoModuleState' = $false
}

foreach ($sqlFile in $sqlFiles) {
    $text = Get-Content -LiteralPath $sqlFile.FullName -Raw
    foreach ($definition in @($opsDefinitionsFound.Keys)) {
        if ($text -match [regex]::Escape($definition)) {
            $opsDefinitionsFound[$definition] = $true
        }
    }
}

foreach ($definition in @($opsDefinitionsFound.Keys)) {
    if (-not $opsDefinitionsFound[$definition]) {
        Add-Failure "Missing required ops definition: $definition"
    }
}

$executionReadmes = [System.Collections.Generic.List[string]]::new()
$topLevelReadme = Join-Path $demoRoot 'README.md'
if (-not (Test-Path -LiteralPath $topLevelReadme -PathType Leaf)) {
    Add-Failure 'Missing DEMO\README.md.'
}
else {
    $executionReadmes.Add($topLevelReadme)
}

foreach ($moduleDirectory in $moduleDirectories) {
    $moduleReadme = Join-Path $moduleDirectory.FullName 'README.md'
    if (-not (Test-Path -LiteralPath $moduleReadme -PathType Leaf)) {
        Add-Failure "Missing module README: $(Resolve-RepoPath -Path $moduleReadme)"
        continue
    }

    $executionReadmes.Add($moduleReadme)
}

if ($executionReadmes.Count -eq 0) {
    Add-Failure 'No demo execution README files were found.'
}
else {
    foreach ($readme in $executionReadmes) {
        Test-ReadmeExecutionTargets -Path $readme
    }
}

$moduleResetFiles = @(
    foreach ($moduleDirectory in $moduleDirectories) {
        Get-ChildItem -Path (Join-Path $moduleDirectory.FullName 'reset') -File -ErrorAction SilentlyContinue
    }
)

if ($moduleResetFiles.Count -eq 0) {
    Add-Failure 'No module reset scripts were found.'
}
else {
    foreach ($resetFile in $moduleResetFiles) {
        Test-PatternAbsent -Path $resetFile.FullName -Pattern 'DROP\s+DATABASE' -FailureMessage "Module reset $(Resolve-RepoPath -Path $resetFile.FullName) still contains DROP DATABASE."
    }
}

$dabConfigPath = Join-Path $demoRoot 'M08\common\dab-config.json'
if (-not (Test-Path -LiteralPath $dabConfigPath -PathType Leaf)) {
    Add-Failure 'Missing Data API Builder configuration file.'
}
else {
    try {
        $dabConfig = Get-Content -LiteralPath $dabConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        $dabConfig = $null
        Add-Failure "Data API Builder configuration could not be parsed: $($_.Exception.Message)"
    }

    if ($null -ne $dabConfig) {
        foreach ($entityName in $expectedDabObjects.Keys) {
            $entity = $dabConfig.entities.$entityName
            if ($null -eq $entity) {
                Add-Failure "DAB entity '$entityName' is missing."
                continue
            }

            $objectName = [string]$entity.source.object
            if ([string]::IsNullOrWhiteSpace($objectName)) {
                Add-Failure "DAB entity '$entityName' does not define a source object."
                continue
            }

            if ($objectName -ne $expectedDabObjects[$entityName]) {
                Add-Failure "DAB entity '$entityName' targets '$objectName' instead of '$($expectedDabObjects[$entityName])'."
            }
        }
    }
}

$publishProfilePath = Join-Path $demoRoot 'M07\common\Dp800.Database\DP800.publish.xml'
if (-not (Test-Path -LiteralPath $publishProfilePath -PathType Leaf)) {
    Add-Failure 'Missing SQL project publish profile.'
}
else {
    try {
        [xml]$publishProfile = Get-Content -LiteralPath $publishProfilePath -Raw
    }
    catch {
        $publishProfile = $null
        Add-Failure "SQL publish profile could not be parsed: $($_.Exception.Message)"
    }

    if ($null -ne $publishProfile) {
        $targetDatabaseName = [string]$publishProfile.Project.PropertyGroup.TargetDatabaseName
        $targetConnectionString = [string]$publishProfile.Project.PropertyGroup.TargetConnectionString

        if ($targetDatabaseName -ne 'AdventureGearAI') {
            Add-Failure "SQL publish profile still targets '$targetDatabaseName' instead of AdventureGearAI."
        }

        if ($targetConnectionString -notmatch 'Database=AdventureGearAI(?:;|$)') {
            Add-Failure 'SQL publish profile connection string does not target AdventureGearAI.'
        }
    }
}

if (-not (Test-Path -LiteralPath $expectedFullReset -PathType Leaf)) {
    Add-Failure "Expected full reset script is missing: $(Resolve-RepoPath -Path $expectedFullReset)"
}
else {
    Test-FullResetScope -Path $expectedFullReset
}

$terraformChanges = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in Get-ChangedFilesInRange -Base $BaseRef -Head $HeadRef) {
    if ($path -like 'TERRAFORM/*' -or $path -like 'TERRAFORM\*') {
        [void]$terraformChanges.Add($path)
    }
}

if ($terraformChanges.Count -gt 0) {
    Add-Failure ("Terraform files are included in git range {0}..{1}: {2}" -f $BaseRef, $HeadRef, ($terraformChanges.ToArray() -join ', '))
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'PASS (all unified demo regression checks succeeded)' -ForegroundColor Green
exit 0
