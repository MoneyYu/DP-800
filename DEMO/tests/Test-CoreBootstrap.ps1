[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$bootstrapRoot = Join-Path $demoRoot 'bootstrap'

$createSql = Join-Path $bootstrapRoot '00-create-adventuregear-database.sql'
$initSql = Join-Path $bootstrapRoot '01-initialize-adventuregear-demo.sql'
$reportSql = Join-Path $bootstrapRoot 'report-legacy-databases.sql'
$bootstrapScript = Join-Path $bootstrapRoot 'Invoke-Bootstrap.ps1'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

function Get-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing required file: $Path"
        return $null
    }
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

Write-Host 'Core bootstrap (AdventureGearAI) unit tests'
Write-Host ''

# --- Legacy assets must be gone -------------------------------------------------
foreach ($legacy in @('00-create-databases.sql', '01-seed-ecommerce.sql')) {
    if (Test-Path -LiteralPath (Join-Path $bootstrapRoot $legacy) -PathType Leaf) {
        Add-Failure "Legacy bootstrap asset still present: $legacy"
    }
}

# --- 00-create-adventuregear-database.sql --------------------------------------
$createText = Get-Text -Path $createSql
Assert-Present -Text $createText -Pattern '(?im)^\s*USE\s+master\s*;' -Message '00-create must run from the master database.'
Assert-Present -Text $createText -Pattern '(?i)IF\s+DB_ID\(N?''AdventureGearAI''\)\s+IS\s+NULL' -Message '00-create must guard the create with an idempotent DB_ID check.'
Assert-Present -Text $createText -Pattern '(?i)CREATE\s+DATABASE\s+\[AdventureGearAI\]' -Message '00-create must create the literal AdventureGearAI database.'
Assert-Absent -Text $createText -Pattern 'DP800_M' -Message '00-create must not reference any legacy DP800_Mxx database.'
Assert-Absent -Text $createText -Pattern '(?i)sp_executesql' -Message '00-create must not use dynamic SQL to create databases.'

# --- 01-initialize-adventuregear-demo.sql --------------------------------------
$initText = Get-Text -Path $initSql
Assert-Present -Text $initText -Pattern '(?im)^\s*USE\s+\[AdventureGearAI\]\s*;' -Message '01-initialize must target the AdventureGearAI database.'
Assert-Absent -Text $initText -Pattern '(?i)CREATE\s+DATABASE' -Message '01-initialize must not create any database.'
Assert-Absent -Text $initText -Pattern 'DP800_M' -Message '01-initialize must not reference any legacy DP800_Mxx database.'

foreach ($schema in 'catalog','sales','customer','security','ops','api','search','ai') {
    Assert-Present -Text $initText -Pattern "(?i)CREATE\s+SCHEMA\s+$schema\b" -Message "01-initialize must create the '$schema' schema."
    Assert-Present -Text $initText -Pattern "(?i)SCHEMA_ID\(N?'$schema'\)\s+IS\s+NULL" -Message "01-initialize must guard the '$schema' schema creation for idempotency."
}

# Operational tracking structures.
Assert-Present -Text $initText -Pattern '(?i)CREATE\s+TABLE\s+ops\.DemoEnvironment' -Message '01-initialize must create ops.DemoEnvironment.'
Assert-Present -Text $initText -Pattern '(?i)PK_DemoEnvironment\s+PRIMARY\s+KEY' -Message 'ops.DemoEnvironment must declare a primary key.'
Assert-Present -Text $initText -Pattern '(?i)CK_DemoEnvironment_DatabaseName' -Message 'ops.DemoEnvironment must constrain its identity to AdventureGearAI.'
Assert-Present -Text $initText -Pattern '(?i)SchemaVersion' -Message 'ops.DemoEnvironment must record a schema version.'

Assert-Present -Text $initText -Pattern '(?i)CREATE\s+TABLE\s+ops\.DemoModuleState' -Message '01-initialize must create ops.DemoModuleState.'
Assert-Present -Text $initText -Pattern '(?i)PK_DemoModuleState\s+PRIMARY\s+KEY' -Message 'ops.DemoModuleState must declare a primary key.'
Assert-Present -Text $initText -Pattern '(?i)CK_DemoModuleState_ModuleNumber\s+CHECK\s*\(ModuleNumber\s+BETWEEN\s+1\s+AND\s+11\)' -Message 'ops.DemoModuleState must constrain ModuleNumber to 1-11.'
Assert-Present -Text $initText -Pattern '(?i)CK_DemoModuleState_Status' -Message 'ops.DemoModuleState must constrain Status values.'
Assert-Present -Text $initText -Pattern '(?i)StartedAtUtc' -Message 'ops.DemoModuleState must track a started timestamp.'
Assert-Present -Text $initText -Pattern '(?i)CompletedAtUtc' -Message 'ops.DemoModuleState must track a completed timestamp.'
Assert-Present -Text $initText -Pattern '(?i)LastError' -Message 'ops.DemoModuleState must track error metadata.'

# Core ecommerce tables.
$coreTables = @(
    'catalog.Categories','catalog.Products','catalog.Inventory',
    'customer.Customers','customer.ProductReviews',
    'sales.Orders','sales.OrderItems'
)
foreach ($table in $coreTables) {
    $escaped = [regex]::Escape($table)
    Assert-Present -Text $initText -Pattern "(?i)CREATE\s+TABLE\s+$escaped\b" -Message "01-initialize must create $table."
}

# Relationship and data-integrity coverage.
Assert-Present -Text $initText -Pattern '(?i)FK_Products_Categories\s+REFERENCES\s+catalog\.Categories' -Message 'catalog.Products must reference catalog.Categories.'
Assert-Present -Text $initText -Pattern '(?i)FK_OrderItems_Orders\s+REFERENCES\s+sales\.Orders' -Message 'sales.OrderItems must reference sales.Orders.'
Assert-Present -Text $initText -Pattern '(?i)FK_Orders_Customers\s+REFERENCES\s+customer\.Customers' -Message 'sales.Orders must reference customer.Customers.'
Assert-Present -Text $initText -Pattern '(?i)ProductMetadata\s+json\s+NULL' -Message 'catalog.Products must use the native json type for ProductMetadata.'
Assert-Present -Text $initText -Pattern '(?i)Preferences\s+json\s+NULL' -Message 'customer.Customers must use the native json type for Preferences.'
Assert-Present -Text $initText -Pattern '(?i)ShippingMetadata\s+json\s+NULL' -Message 'sales.Orders must use the native json type for ShippingMetadata.'
Assert-Absent -Text $initText -Pattern '(?i)ISJSON\s*\(' -Message 'Native json columns must not retain redundant ISJSON check expressions.'
Assert-Present -Text $initText -Pattern '(?i)(compatibility_level|@compatibilityLevel)\s*<\s*170' -Message '01-initialize must fail clearly below compatibility level 170.'
Assert-Present -Text $initText -Pattern '(?i)ALTER\s+TABLE\s+catalog\.Products\s+ALTER\s+COLUMN\s+ProductMetadata\s+json' -Message '01-initialize must upgrade legacy ProductMetadata to native json.'
Assert-Present -Text $initText -Pattern '(?i)ALTER\s+TABLE\s+customer\.Customers\s+ALTER\s+COLUMN\s+Preferences\s+json' -Message '01-initialize must upgrade legacy Preferences to native json.'
Assert-Present -Text $initText -Pattern '(?i)ALTER\s+TABLE\s+sales\.Orders\s+ALTER\s+COLUMN\s+ShippingMetadata\s+json' -Message '01-initialize must upgrade legacy ShippingMetadata to native json.'
Assert-Present -Text $initText -Pattern '(?i)SchemaVersion.*2\.1\.0-json170-seedownership' -Message '01-initialize must record the native-json seed-ownership schema version.'
Assert-Present -Text $initText -Pattern '(?i)CK_ProductReviews_Rating\s+CHECK\s*\(Rating\s+BETWEEN\s+1\s+AND\s+5\)' -Message 'customer.ProductReviews must constrain Rating 1-5.'

# Bootstrap may enrich only rows whose deterministic ownership is recorded.
Assert-Present -Text $initText -Pattern '(?i)CREATE\s+TABLE\s+ops\.BootstrapSeedRegistry' -Message '01-initialize must create the bootstrap seed ownership registry.'
Assert-Present -Text $initText -Pattern '(?i)PK_BootstrapSeedRegistry\s+PRIMARY\s+KEY' -Message 'The bootstrap seed ownership registry must have a primary key.'
Assert-Present -Text $initText -Pattern '(?i)SeedVersion' -Message 'The bootstrap seed ownership registry must record its seed version.'
Assert-Present -Text $initText -Pattern '(?i)JOIN\s+ops\.BootstrapSeedRegistry\s+AS\s+ownership' -Message 'JSON enrichment must join the bootstrap seed ownership registry.'

# Module state seed covers all eleven modules.
Assert-Present -Text $initText -Pattern '(?i)INSERT\s+ops\.DemoModuleState' -Message '01-initialize must seed ops.DemoModuleState.'
Assert-Present -Text $initText -Pattern '\(11\)' -Message 'ops.DemoModuleState seed must include module 11.'

# No M01 advanced/module-specific objects yet.
Assert-Absent -Text $initText -Pattern '(?i)VECTOR|EXTERNAL\s+MODEL|FULLTEXT' -Message '01-initialize must not include module-specific advanced objects yet.'

# --- report-legacy-databases.sql -----------------------------------------------
$reportText = Get-Text -Path $reportSql
Assert-Present -Text $reportText -Pattern '(?i)sys\.databases' -Message 'report-legacy-databases must inspect sys.databases.'
Assert-Absent -Text $reportText -Pattern '(?i)DROP\s+DATABASE|CREATE\s+DATABASE|ALTER\s+DATABASE' -Message 'report-legacy-databases must never create/alter/drop databases.'

# --- Invoke-Bootstrap.ps1 (AST literal-target enforcement) ----------------------
$bootstrapText = Get-Text -Path $bootstrapScript
Assert-Absent -Text $bootstrapText -Pattern '00-create-databases\.sql|01-seed-ecommerce\.sql' -Message 'Invoke-Bootstrap must not reference legacy bootstrap assets.'
Assert-Present -Text $bootstrapText -Pattern '00-create-adventuregear-database\.sql' -Message 'Invoke-Bootstrap must wire the create-database asset.'
Assert-Present -Text $bootstrapText -Pattern '01-initialize-adventuregear-demo\.sql' -Message 'Invoke-Bootstrap must wire the initialization asset.'

if ($null -ne $bootstrapText) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapScript, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($pe in $parseErrors) { Add-Failure "Invoke-Bootstrap parse error: $($pe.Message)" }
    }
    else {
        $allowed = @('master', 'AdventureGearAI')
        $sawMaster = $false
        $sawAdventure = $false
        $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($command in $commands) {
            $elements = @($command.CommandElements)
            for ($i = 0; $i -lt $elements.Count; $i++) {
                $element = $elements[$i]
                if ($element -isnot [System.Management.Automation.Language.CommandParameterAst] -or $element.ParameterName -ine 'Database') { continue }
                $argument = $element.Argument
                if ($null -eq $argument -and ($i + 1) -lt $elements.Count) { $argument = $elements[$i + 1] }
                if ($argument -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    Add-Failure "Invoke-Bootstrap -Database target must be a literal; found: $($argument.Extent.Text)"
                    continue
                }
                if ($argument.Value -notin $allowed) {
                    Add-Failure "Invoke-Bootstrap uses a forbidden -Database target: $($argument.Value)"
                }
                if ($argument.Value -eq 'master') { $sawMaster = $true }
                if ($argument.Value -eq 'AdventureGearAI') { $sawAdventure = $true }
            }
        }
        if (-not $sawMaster) { Add-Failure 'Invoke-Bootstrap must invoke create against literal master.' }
        if (-not $sawAdventure) { Add-Failure 'Invoke-Bootstrap must invoke initialization against literal AdventureGearAI.' }
    }
}

# --- Behavioral guards -----------------------------------------------------------
# Module execution is now wired to the dependency-aware runner (Task 3). The
# bootstrap must delegate to Invoke-DemoModule.ps1 after core init rather than
# throwing, so assert the wiring statically (executing it would require a live
# database) and confirm the old "not available" guard message is gone.
Assert-Present -Text $bootstrapText -Pattern 'Invoke-DemoModule\.ps1' -Message 'Invoke-Bootstrap must delegate module execution to Invoke-DemoModule.ps1.'
Assert-Present -Text $bootstrapText -Pattern '(?i)-SkipCoreBootstrap' -Message 'Invoke-Bootstrap must call the module runner with -SkipCoreBootstrap to avoid recursion.'
Assert-Absent -Text $bootstrapText -Pattern 'per-module runner is not available' -Message 'Invoke-Bootstrap must no longer throw the retired "per-module runner is not available" message.'
# Hybrid integration guard: no child pwsh process for module delegation (int[] would be serialized/lost).
Assert-Absent -Text $bootstrapText -Pattern '(?i)pwsh[^\n]*-File[^\n]*Invoke-DemoModule' -Message 'Invoke-Bootstrap must NOT use pwsh -File to delegate modules (multi-element [int[]] values would be concatenated/lost at the process boundary).'
Assert-Present -Text $bootstrapText -Pattern '(?i)\.\s+\$moduleRunner' -Message 'Invoke-Bootstrap must dot-source $moduleRunner to keep [int[]] intact in the current process.'
Assert-Present -Text $bootstrapText -Pattern '(?i)Invoke-DemoModuleRunner\s' -Message 'Invoke-Bootstrap must call Invoke-DemoModuleRunner directly after dot-sourcing the runner.'

$guardDatabase = & pwsh -NoProfile -File $bootstrapScript -Database ReportingSandbox 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) {
    Add-Failure 'Invoke-Bootstrap must fail when -Database is not AdventureGearAI.'
}
elseif ($guardDatabase -notmatch 'only the AdventureGearAI database') {
    Add-Failure "Invoke-Bootstrap -Database guard message is not explicit. Output: $guardDatabase"
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all core bootstrap unit checks succeeded)' -ForegroundColor Green
exit 0
