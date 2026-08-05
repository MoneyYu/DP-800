[CmdletBinding()]
param()

# ---------------------------------------------------------------------------
# Focused static regression for the migrated M01-M06 demos. It validates ONLY
# the M01-M06 modules, their manifest entries (1-6), and their READMEs against
# the AdventureGearAI single-database contract. It does not touch M07-M11, the
# bootstrap/core/runner, reset scripts, or Terraform, so it can run independently
# of the concurrently migrated later modules. No database connection is required.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$manifestPath = Join-Path $demoRoot 'scripts\module-manifest.json'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { Add-Failure $Message } }
function Get-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Failure "Missing required file: $Path"; return $null }
    return Get-Content -LiteralPath $Path -Raw
}
function Assert-Present { param([string]$Text, [string]$Pattern, [string]$Message) if ($null -ne $Text -and $Text -notmatch $Pattern) { Add-Failure $Message } }
function Assert-Absent { param([string]$Text, [string]$Pattern, [string]$Message) if ($null -ne $Text -and $Text -match $Pattern) { Add-Failure $Message } }

Write-Host 'Focused M01-M06 AdventureGearAI static regression'
Write-Host ''

$demoSchemas = 'catalog', 'sales', 'customer', 'security', 'ops'

# Expected manifest setup arrays for the migrated modules. M06 lists only the
# non-interactive local script; the blocker/deadlock/observer scripts are
# intentionally excluded from the runner's normal setup.
$expectedSetup = @{
    1 = @{ common = @('../M01/common/01-objects.sql', '../M01/common/02-specialized-tables.sql'); local = @('../M01/local/01-inspect.sql', '../M01/local/02-inspect-specialized.sql') }
    2 = @{ common = @('../M02/common/01-programmability.sql'); local = @('../M02/local/01-exercise.sql') }
    3 = @{ common = @('../M03/common/01-advanced-objects.sql'); local = @('../M03/local/01-advanced-queries.sql') }
    4 = @{ common = @(); local = @('../M04/local/01-review-target.sql', '../M04/local/02-reference-improvement.sql') }
    5 = @{ common = @('../M05/common/01-security.sql'); local = @('../M05/local/01-verify-security.sql') }
    6 = @{ common = @('../M06/common/01-workload.sql'); local = @('../M06/local/01-plans-query-store-dmvs.sql') }
}

# Interactive M06 scripts that MUST NOT appear in any manifest setup list.
$interactiveM06 = @(
    '02-blocker.sql', '03-blocked.sql', '04-observe-blocking.sql',
    '05-deadlock-session-a.sql', '06-deadlock-session-b.sql'
)

# --- 1) Manifest entries 1-6 ------------------------------------------------
$manifestText = Get-Text -Path $manifestPath
$manifest = $null
if ($null -ne $manifestText) {
    try { $manifest = $manifestText | ConvertFrom-Json }
    catch { Add-Failure "module-manifest.json is not valid JSON: $($_.Exception.Message)" }
}

if ($null -ne $manifest) {
    $manifestDir = Split-Path -Parent $manifestPath
    foreach ($module in $expectedSetup.Keys) {
        $entry = $manifest.modules | Where-Object { [int]$_.module -eq $module }
        if ($null -eq $entry) { Add-Failure "Manifest is missing an entry for module $module."; continue }

        Assert-True -Condition ([bool]$entry.ready) -Message "M$('{0:d2}' -f $module) manifest entry must be ready=true."

        foreach ($scope in 'common', 'local') {
            $actual = @()
            if ($entry.setup -and ($entry.setup.PSObject.Properties.Name -contains $scope)) { $actual = @($entry.setup.$scope) }
            $expected = @($expectedSetup[$module][$scope])
            Assert-True -Condition (($actual -join '|') -eq ($expected -join '|')) `
                -Message "M$('{0:d2}' -f $module) manifest $scope setup is '$($actual -join ', ')' but expected '$($expected -join ', ')'."

            foreach ($relative in $actual) {
                $resolved = Join-Path $manifestDir $relative
                Assert-True -Condition (Test-Path -LiteralPath $resolved -PathType Leaf) -Message "M$('{0:d2}' -f $module) manifest $scope references a missing file: $relative"
            }
        }

        # Azure scope is never part of a local run.
        $azure = @()
        if ($entry.setup -and ($entry.setup.PSObject.Properties.Name -contains 'azure')) { $azure = @($entry.setup.azure) }
        Assert-True -Condition ($azure.Count -eq 0) -Message "M$('{0:d2}' -f $module) manifest must not list azure scripts for the local demo."

        # No interactive M06 script may be listed in any scope.
        $allListed = @()
        foreach ($scope in 'common', 'local', 'azure') {
            if ($entry.setup -and ($entry.setup.PSObject.Properties.Name -contains $scope)) { $allListed += @($entry.setup.$scope) }
        }
        foreach ($listed in $allListed) {
            foreach ($interactive in $interactiveM06) {
                Assert-Absent -Text $listed -Pattern ([regex]::Escape($interactive)) -Message "M$('{0:d2}' -f $module) manifest must not list interactive M06 script $interactive."
            }
        }
    }
}

# --- 2) Every M01-M06 setup SQL file is migrated to AdventureGearAI ----------
$setupSqlFiles = foreach ($module in $expectedSetup.Keys) {
    foreach ($scope in 'common', 'local') {
        foreach ($relative in @($expectedSetup[$module][$scope])) {
            Join-Path (Split-Path -Parent $manifestPath) $relative
        }
    }
}

foreach ($sqlPath in $setupSqlFiles) {
    $text = Get-Text -Path $sqlPath
    if ($null -eq $text) { continue }
    $leaf = Split-Path -Leaf $sqlPath

    # No legacy per-database name and no legacy dbo object references.
    Assert-Absent -Text $text -Pattern 'DP800_M\d{2}' -Message "$leaf still references a legacy DP800_Mxx database."
    Assert-Absent -Text $text -Pattern '(?i)\bdbo\.' -Message "$leaf still references a legacy dbo.* object; use AdventureGearAI domain schemas."

    # No per-database DDL: modules operate inside the single AdventureGearAI
    # database. ALTER DATABASE CURRENT (e.g. Query Store) is permitted.
    Assert-Absent -Text $text -Pattern '(?im)\b(CREATE|DROP)\s+DATABASE\b' -Message "$leaf must not issue CREATE/DROP DATABASE."
    Assert-Absent -Text $text -Pattern '(?im)\bALTER\s+DATABASE\s+(?!CURRENT\b)' -Message "$leaf must only ALTER DATABASE CURRENT, never a named database."
    Assert-Absent -Text $text -Pattern '(?im)^\s*USE\s+' -Message "$leaf must not switch databases with USE."

    # At least one demo domain schema must be referenced.
    $referencesSchema = $false
    foreach ($schema in $demoSchemas) {
        if ($text -match ("(?i)\b" + [regex]::Escape($schema) + "\.")) { $referencesSchema = $true; break }
    }
    Assert-True -Condition $referencesSchema -Message "$leaf does not reference any AdventureGearAI domain schema (catalog/sales/customer/security/ops)."
}

# --- 3) Key migrated objects live in the right domain schema ----------------
$expectedContent = @{
    'M01\common\01-objects.sql'          = @('catalog\.ProductPrice', 'SYSTEM_VERSIONING\s*=\s*ON', 'catalog\.ProductPriceHistory', 'sales\.PartitionedOrders', 'AS\s+NODE', 'AS\s+EDGE', 'JSON_VALUE')
    'M02\common\01-programmability.sql'  = @('sales\.OrderStatusAudit', 'sales\.vw_CustomerOrderSummary', 'sales\.fn_OrderTotal', 'sales\.fn_CustomerOrders', 'sales\.usp_AddOrderItem', 'sales\.trg_OrderStatusAudit', 'ON\s+sales\.Orders')
    'M02\local\01-exercise.sql'          = @('ROLLBACK')
    'M03\common\01-advanced-objects.sql' = @('ops\.EmployeeHierarchy', 'AS\s+NODE', 'AS\s+EDGE')
    'M03\local\01-advanced-queries.sql'  = @('OVER\s*\(', 'OPENJSON', 'SOUNDEX', 'MATCH', 'REGEXP_LIKE', 'catalog\.Products', 'customer\.Customers')
    'M05\common\01-security.sql'         = @('security\.SecureCustomers', 'MASKED\s+WITH', 'security\.fn_RegionFilter', 'security\.CustomerRegionPolicy', 'customer\.Customers')
    'M05\local\01-verify-security.sql'   = @('EXECUTE\s+AS\s+USER', 'security\.SecureCustomers')
    'M06\common\01-workload.sql'         = @('ops\.PerformanceOrders', 'catalog\.Products', 'customer\.Customers', 'QUERY_STORE\s*=\s*ON')
    'M06\local\01-plans-query-store-dmvs.sql' = @('ops\.PerformanceOrders', 'sys\.dm_exec_query_stats', 'sys\.database_query_store_options')
}
foreach ($relative in $expectedContent.Keys) {
    $path = Join-Path $demoRoot $relative
    $text = Get-Text -Path $path
    if ($null -eq $text) { continue }
    foreach ($pattern in $expectedContent[$relative]) {
        Assert-Present -Text $text -Pattern $pattern -Message "$relative is missing expected migrated content matching /$pattern/."
    }
}

# The M05 companion projection must not replace the canonical customer table.
$m05 = Get-Text -Path (Join-Path $demoRoot 'M05\common\01-security.sql')
Assert-Absent -Text $m05 -Pattern '(?i)DROP\s+TABLE[^;]*customer\.Customers' -Message 'M05 must not drop the canonical customer.Customers table.'
Assert-Present -Text $m05 -Pattern '(?i)DROP\s+USER\s+IF\s+EXISTS' -Message 'M05 users must be resettable (DROP USER IF EXISTS before CREATE USER).'

# --- 4) M06 interactive scripts are migrated but kept out of the manifest ----
# The blocker/blocked/deadlock scripts operate on ops.PerformanceOrders; the
# observer script (04) only inspects DMVs, so it has no table reference.
$interactiveWithTable = @('02-blocker.sql', '03-blocked.sql', '05-deadlock-session-a.sql', '06-deadlock-session-b.sql')
foreach ($interactive in $interactiveM06) {
    $path = Join-Path $demoRoot (Join-Path 'M06\local' $interactive)
    $text = Get-Text -Path $path
    if ($null -eq $text) { continue }
    if ($interactiveWithTable -contains $interactive) {
        Assert-Present -Text $text -Pattern 'ops\.PerformanceOrders' -Message "Interactive M06 script $interactive must target ops.PerformanceOrders."
    }
    Assert-Absent -Text $text -Pattern '(?i)\bdbo\.' -Message "Interactive M06 script $interactive still references a legacy dbo.* object."
}

# --- 5) READMEs point at AdventureGearAI + the hybrid runner -----------------
foreach ($module in $expectedSetup.Keys) {
    $moduleName = 'M{0:d2}' -f $module
    $readme = Join-Path $demoRoot (Join-Path $moduleName 'README.md')
    $text = Get-Text -Path $readme
    if ($null -eq $text) { continue }
    Assert-Present -Text $text -Pattern 'AdventureGearAI' -Message "$moduleName README must name the AdventureGearAI execution target."
    Assert-Present -Text $text -Pattern 'Invoke-DemoModule\.ps1' -Message "$moduleName README must document the hybrid runner command."
    Assert-Present -Text $text -Pattern "-Modules\s+$module\b" -Message "$moduleName README runner command must request -Modules $module."
    # DP800_Mxx must never appear as an execution/connection target (legacy prose is allowed).
    foreach ($line in ($text -split "\r?\n")) {
        if ($line -match 'DP800_M\d{2}') {
            Assert-True -Condition ($line -match '(?i)legacy|cleanup|never automatically') -Message "$moduleName README references a DP800_Mxx target outside legacy-cleanup prose: $line"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all focused M01-M06 static checks succeeded)' -ForegroundColor Green
exit 0
