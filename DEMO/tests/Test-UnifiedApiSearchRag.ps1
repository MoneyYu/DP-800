[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Focused static/unit tests for the migrated API (M08), search (M10), embeddings
# (M09), CI/CD SQL project (M07), and RAG (M11) modules. These assert the
# AdventureGearAI domain-schema migration without needing a live database.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$scriptsRoot = Join-Path $demoRoot 'scripts'
$runnerScript = Join-Path $scriptsRoot 'Invoke-DemoModule.ps1'
$orchestratorScript = Join-Path $PSScriptRoot 'Invoke-AllUnifiedDemoTests.ps1'
$manifestJson = Join-Path $scriptsRoot 'module-manifest.json'
$dabConfigPath = Join-Path $demoRoot 'M08\common\dab-config.json'
$dabRuntimeTestPath = Join-Path $PSScriptRoot 'Test-DabIntegrationRuntime.ps1'
$dabLocalReadmePath = Join-Path $demoRoot 'M08\local\README.md'
$dabLocalReadmeZhTwPath = Join-Path $demoRoot 'M08\local\README.zh-TW.md'
$publishProfilePath = Join-Path $demoRoot 'M07\common\Dp800.Database\DP800.publish.xml'
$sqlProject = Join-Path $demoRoot 'M07\common\Dp800.Database\Dp800.Database.sqlproj'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { Add-Failure "$Message Expected '$Expected' but got '$Actual'." }
}
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { Add-Failure $Message } }
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

Write-Host 'Unified API/search/RAG (M07-M11) static tests'
Write-Host ''

# Dot-source the runner so its pure resolution/manifest helpers are available.
. $runnerScript

# --- 1) Manifest JSON parses and entries 7-11 are ready with real setup -------
$manifestText = Get-Text -Path $manifestJson
$manifest = $null
if ($null -ne $manifestText) {
    try { $manifest = $manifestText | ConvertFrom-Json }
    catch { Add-Failure "module-manifest.json is not valid JSON: $($_.Exception.Message)" }
}

$manifestMap = $null
if ($null -ne $manifest) {
    $manifestMap = Read-DemoModuleManifest -Path $manifestJson
    foreach ($module in 7, 8, 9, 10, 11) {
        $entry = $manifestMap[$module]
        Assert-True -Condition ($null -ne $entry) -Message "Manifest is missing entry for M$('{0:d2}' -f $module)."
        if ($null -eq $entry) { continue }
        Assert-True -Condition $entry.Ready -Message "M$('{0:d2}' -f $module) must be ready=true after migration."
        $localSetupCount = @($entry.Scripts['common']).Where({ $_ }).Count + @($entry.Scripts['local']).Where({ $_ }).Count
        Assert-True -Condition ($localSetupCount -ge 1) -Message "M$('{0:d2}' -f $module) must list at least one common/local setup script."
    }
    # Modules owned by the other agent must not be disturbed by this task.
    foreach ($module in 1, 2, 3, 4, 5, 6) {
        Assert-True -Condition ($null -ne $manifestMap[$module]) -Message "Manifest must still contain entry for M$('{0:d2}' -f $module)."
    }
}

# --- 2) No azure scripts are executed by the local runner ---------------------
if ($null -ne $manifestMap) {
    foreach ($module in 7, 8, 9, 10, 11) {
        $localScripts = Get-DemoModuleSetupScripts -Manifest $manifestMap -Module $module -Scope 'local'
        foreach ($script in $localScripts) {
            Assert-Absent -Text $script -Pattern '(?i)[\\/]azure[\\/]' -Message "M$('{0:d2}' -f $module) local run must never execute an azure script: $script"
        }
        # But azure scripts, where present, must still be truthfully recorded.
        $entry = $manifestMap[$module]
        if ($module -in 9, 10, 11) {
            Assert-True -Condition (@($entry.Scripts['azure']).Where({ $_ }).Count -ge 1) -Message "M$('{0:d2}' -f $module) should record its azure script in the manifest (excluded from local)."
        }
    }
}

# --- 3) Dependency resolution: cumulative M07-M11 and direct M11 --------------
Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested @(7, 8, 9, 10, 11)) -join ',') -Expected '1,7,8,9,10,11' -Message 'Cumulative M07-M11 must resolve M01 first then ascending 7..11.'
Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested 11) -join ',') -Expected '1,9,10,11' -Message 'Direct M11 must resolve M01,M09,M10,M11 in dependency order.'
Assert-Equal -Actual ((Resolve-DemoModuleExecutionPlan -Requested 7) -join ',') -Expected '1,7' -Message 'M07 depends only on core+M01.'

# --- 4) DAB config parses and splits relationship and read-model entities -----
$dabText = Get-Text -Path $dabConfigPath
$dab = $null
if ($null -ne $dabText) {
    try { $dab = $dabText | ConvertFrom-Json }
    catch { Add-Failure "dab-config.json is not valid JSON: $($_.Exception.Message)" }
}
if ($null -ne $dab) {
    $expectedSources = @{
        Category              = 'catalog.Categories'
        Product               = 'catalog.Products'
        ProductCatalog        = 'api.ProductCatalog'
        InventoryAvailability = 'api.InventoryAvailability'
    }
    foreach ($entityName in $expectedSources.Keys) {
        $entity = $dab.entities.$entityName
        Assert-True -Condition ($null -ne $entity) -Message "DAB entity '$entityName' is missing."
        if ($null -eq $entity) { continue }
        Assert-Equal -Actual ([string]$entity.source.object) -Expected $expectedSources[$entityName] -Message "DAB entity '$entityName' must source its configured DAB contract object."
    }
    $expectedProductMappings = @{
        ProductID   = 'id'
        ProductName = 'name'
        UnitPrice   = 'price'
    }
    foreach ($mappingName in $expectedProductMappings.Keys) {
        Assert-Equal -Actual ([string]$dab.entities.Product.mappings.$mappingName) -Expected $expectedProductMappings[$mappingName] -Message "DAB Product mapping '$mappingName' must be preserved."
    }
    Assert-True -Condition ($null -eq $dab.entities.Product.mappings.PSObject.Properties['UnitsInStock']) -Message 'DAB Product must not map UnitsInStock because catalog.Products does not contain that column.'
    # Connection string must come from the environment, not a literal secret.
    Assert-Equal -Actual ([string]$dab.'data-source'.'connection-string') -Expected "@env('DATABASE_CONNECTION_STRING')" -Message 'DAB connection string must be sourced from the environment only.'
}
$dabRuntimeTest = Get-Text -Path $dabRuntimeTestPath
Assert-Present -Text $dabRuntimeTest -Pattern 'Microsoft\.DataApiBuilder' -Message 'DAB must have a database-connected runtime integration test.'
Assert-Present -Text $dabRuntimeTest -Pattern '2\.0\.9' -Message 'DAB runtime integration test must pin Microsoft.DataApiBuilder 2.0.9.'
Assert-Present -Text $dabRuntimeTest -Pattern 'DATABASE_CONNECTION_STRING' -Message 'DAB runtime integration test must use the process-scoped connection string.'
foreach ($readmePath in $dabLocalReadmePath, $dabLocalReadmeZhTwPath) {
    $readmeText = Get-Text -Path $readmePath
    Assert-Present -Text $readmeText -Pattern 'Microsoft\.DataApiBuilder.*--version\s+2\.0\.9' -Message "$readmePath must pin the DAB CLI version to 2.0.9."
    Assert-Present -Text $readmeText -Pattern '(?i)runtime.*test|執行階段.*測試' -Message "$readmePath must document the DAB runtime integration test."
}
$orchestratorText = Get-Text -Path $orchestratorScript
Assert-Present -Text $orchestratorText -Pattern "'Test-DabIntegrationRuntime\.ps1'" -Message 'The unified test orchestrator must explicitly run the DAB runtime integration test.'
# The migrated API script must not recreate duplicate Api tables.
$apiSql = Get-Text -Path (Join-Path $demoRoot 'M08\common\01-product-api.sql')
Assert-Absent -Text $apiSql -Pattern '(?i)CREATE\s+TABLE\s+dbo\.ApiProducts' -Message 'M08 must not create a duplicate dbo.ApiProducts table.'
Assert-Absent -Text $apiSql -Pattern '(?i)CREATE\s+TABLE\s+dbo\.ApiCategories' -Message 'M08 must not create a duplicate dbo.ApiCategories table.'
Assert-Present -Text $apiSql -Pattern '(?i)CREATE\s+OR\s+ALTER\s+VIEW\s+api\.Products' -Message 'M08 must create api.Products over the catalog.'

# --- 5) M07 SQL project targets AdventureGearAI ------------------------------
$publishText = Get-Text -Path $publishProfilePath
if ($null -ne $publishText) {
    [xml]$publishXml = $publishText
    Assert-Equal -Actual ([string]$publishXml.Project.PropertyGroup.TargetDatabaseName) -Expected 'AdventureGearAI' -Message 'M07 publish profile must target AdventureGearAI.'
    Assert-Present -Text ([string]$publishXml.Project.PropertyGroup.TargetConnectionString) -Pattern 'Database=AdventureGearAI(?:;|$)' -Message 'M07 publish connection string must target AdventureGearAI.'
}

# --- 6) READMEs target AdventureGearAI and never a legacy per-module database --
foreach ($module in 7, 8, 9, 10, 11) {
    $readme = Join-Path $demoRoot ("M{0:d2}\README.md" -f $module)
    $text = Get-Text -Path $readme
    Assert-Present -Text $text -Pattern 'AdventureGearAI' -Message "M$('{0:d2}' -f $module) README must reference AdventureGearAI."
    Assert-Absent -Text $text -Pattern 'DP800_M\d{2}' -Message "M$('{0:d2}' -f $module) README must not reference a legacy DP800_Mxx database."
}

# --- 7) Platform feature skips are truthful (feature detection emits reasons) --
$m09Local = Get-Text -Path (Join-Path $demoRoot 'M09\local\01-feature-detection.sql')
Assert-Present -Text $m09Local -Pattern '(?i)skipped' -Message 'M09 local feature detection must emit a truthful skip result.'
Assert-Present -Text $m09Local -Pattern '(?i)ERROR_MESSAGE\(\)' -Message 'M09 local feature detection must surface the real error reason.'
$m10Local = Get-Text -Path (Join-Path $demoRoot 'M10\local\01-search.sql')
Assert-Present -Text $m10Local -Pattern '(?i)Full-text search skipped' -Message 'M10 local must truthfully skip full-text when it is not installed.'
Assert-Present -Text $m10Local -Pattern '(?i)Hybrid search skipped' -Message 'M10 local must truthfully skip hybrid search when a feature is missing.'
Assert-Absent -Text $m10Local -Pattern '(?i)WITH\s+APPROXIMATE' -Message 'M10 local (exact) must NOT use the Azure DiskANN WITH APPROXIMATE syntax.'
$m10Azure = Get-Text -Path (Join-Path $demoRoot 'M10\azure\01-ann-search.sql')
Assert-Present -Text $m10Azure -Pattern '(?i)WITH\s+APPROXIMATE' -Message 'M10 azure must use the DiskANN WITH APPROXIMATE syntax.'
Assert-Present -Text $m10Azure -Pattern '(?i)search\.SearchDocuments' -Message 'M10 azure must operate on the search schema.'

# --- 8) Protect passwords and other databases --------------------------------
$ownedSql = @(
    Get-ChildItem -Path (Join-Path $demoRoot 'M07'), (Join-Path $demoRoot 'M08'), (Join-Path $demoRoot 'M09'), (Join-Path $demoRoot 'M10'), (Join-Path $demoRoot 'M11') -Recurse -File -Include '*.sql' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]reset[\\/]' -and $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }
)
foreach ($file in $ownedSql) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    # No embedded passwords / secrets.
    Assert-Absent -Text $text -Pattern '(?i)(PWD|PASSWORD)\s*=\s*[''"]?[^''";\s@$]' -Message "$($file.Name) must not embed a password literal."
    # No cross-database targeting or destructive DB commands outside reset (Task 6).
    Assert-Absent -Text $text -Pattern '(?i)DROP\s+DATABASE' -Message "$($file.Name) must not drop a database."
    Assert-Absent -Text $text -Pattern 'DP800_M\d{2}' -Message "$($file.Name) must not reference a legacy per-module database."
    Assert-Absent -Text $text -Pattern '(?im)^\s*USE\s+\[?(?!AdventureGearAI\b|master\b)[A-Za-z]' -Message "$($file.Name) must only USE AdventureGearAI (or master)."
}

# --- 9) M07 SQL project builds with 0 warnings/errors ------------------------
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Write-Host 'SKIP: dotnet is not available; M07 build check skipped.' -ForegroundColor Yellow
}
else {
    $buildOutput = & $dotnet.Source build $sqlProject -v q --nologo 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Failure "M07 SQL project build failed. Output: $buildOutput" }
    if ($buildOutput -notmatch '0 Warning\(s\)') { Add-Failure "M07 SQL project build reported warnings. Output: $buildOutput" }
    if ($buildOutput -notmatch '0 Error\(s\)') { Add-Failure "M07 SQL project build reported errors. Output: $buildOutput" }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all M07-M11 static checks succeeded)' -ForegroundColor Green
exit 0
