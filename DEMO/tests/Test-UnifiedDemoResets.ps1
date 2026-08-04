[CmdletBinding()]
param()

# ---------------------------------------------------------------------------
# Focused static regression for Task 6: the module-scoped reset scripts and the
# approved full (database-level) reset workflow for the unified AdventureGearAI
# demo. No database connection is required. It asserts:
#   * every module reset removes ONLY its own objects, never a database and never
#     a canonical core table, and guards the AdventureGearAI DB/marker first;
#   * dependency/staleness reset scope (M01 -> M02..M11; M09 -> M10/M11;
#     M10 -> M11; every other module -> itself), using only allowed status values
#     and clearing timestamps/errors;
#   * exactly one reset asset (DEMO/reset/reset-adventuregear.sql) may contain
#     DROP DATABASE, and it targets the literal AdventureGearAI only;
#   * the full reset wrapper is hard-scoped (literal master/AdventureGearAI, the
#     literal SQL asset, no arbitrary database parameter) and re-bootstraps core.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$fullResetWrapper = Join-Path $demoRoot 'reset\Reset-AdventureGearAI.ps1'
$fullResetSql = Join-Path $demoRoot 'reset\reset-adventuregear.sql'

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

Write-Host 'Task 6 static regression: scoped and full AdventureGearAI reset workflows'
Write-Host ''

# Objects each module must remove (drop) in its reset script.
$expectedDrops = @{
    1  = @('catalog.ProductRelatedTo', 'catalog.ProductNode', 'catalog.ProductPrice', 'catalog.ProductPriceHistory', 'sales.PartitionedOrders', 'PS_AdventureGear_OrderDate', 'PF_AdventureGear_OrderDate', 'IX_Products_MetadataFrame', 'MetadataFrame')
    2  = @('sales.trg_OrderStatusAudit', 'sales.usp_AddOrderItem', 'sales.fn_OrderTotal', 'sales.fn_CustomerOrders', 'sales.vw_CustomerOrderSummary', 'sales.OrderStatusAudit')
    3  = @('ops.ReportsTo', 'ops.EmployeeNode', 'ops.EmployeeHierarchy')
    4  = @()
    5  = @('security.CustomerRegionPolicy', 'security.fn_RegionFilter', 'AdventureGearMaskedReader', 'AdventureGearWestReader', 'security.SecureCustomers')
    6  = @('ops.PerformanceOrders')
    7  = @('catalog.usp_LogInventoryChange', 'catalog.InventoryChangeLog', 'ops.DeploymentLog')
    8  = @('api.InventoryAvailability', 'api.ProductCatalog', 'api.Products', 'api.Categories')
    9  = @('AdventureGearEmbeddingModel', 'ai.VectorFeatureProbe', 'ai.EmbeddingDocuments')
    10 = @('IX_AdventureGear_SearchVector', 'AdventureGearSearchCatalog', 'search.SearchDocuments')
    11 = @('ai.usp_AskProductQuestion', 'ai.usp_BuildRagPrompt')
}

# Module numbers each reset must return to NotStarted (self + dependents/stale).
$expectedStateScope = @{
    1  = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    2  = @(2)
    3  = @(3)
    4  = @(4)
    5  = @(5)
    6  = @(6)
    7  = @(7)
    8  = @(8)
    9  = @(9, 10, 11)
    10 = @(10, 11)
    11 = @(11)
}

# Canonical core objects that a module reset must never drop or empty.
$protectedCore = @(
    'catalog.Products', 'catalog.Categories', 'catalog.Inventory',
    'customer.Customers', 'customer.ProductReviews',
    'sales.Orders', 'sales.OrderItems',
    'ops.DemoEnvironment', 'ops.DemoModuleState'
)

foreach ($module in 1..11) {
    $name = 'M{0:d2}' -f $module
    $path = Join-Path $demoRoot ("$name\reset\reset.sql")
    $text = Get-Text -Path $path
    if ($null -eq $text) { continue }

    # 1) No database-level destruction and no legacy per-module targeting.
    Assert-Absent -Text $text -Pattern '(?i)DROP\s+DATABASE' -Message "$name reset must not contain DROP DATABASE."
    Assert-Absent -Text $text -Pattern 'DP800_M\d{2}' -Message "$name reset must not reference a legacy DP800_Mxx database."
    Assert-Absent -Text $text -Pattern '(?im)^\s*USE\s+\[?(?!AdventureGearAI\b|master\b)[A-Za-z]' -Message "$name reset must only USE AdventureGearAI (never another database)."
    Assert-Absent -Text $text -Pattern '(?i)(PWD|PASSWORD)\s*=\s*[''"]?[^''";\s@$]' -Message "$name reset must not embed a password literal."

    # 2) DB/marker guard is present before any teardown.
    Assert-Present -Text $text -Pattern "(?i)DB_NAME\(\)\s*<>\s*N'AdventureGearAI'" -Message "$name reset must guard the AdventureGearAI database name first."
    Assert-Present -Text $text -Pattern '(?i)ops\.DemoEnvironment' -Message "$name reset must guard the ops.DemoEnvironment marker."

    # 3) Owned objects are dropped.
    foreach ($obj in $expectedDrops[$module]) {
        Assert-Present -Text $text -Pattern ([regex]::Escape($obj)) -Message "$name reset must remove its owned object '$obj'."
    }

    # 4) Canonical core is never dropped or emptied.
    foreach ($core in $protectedCore) {
        Assert-Absent -Text $text -Pattern ("(?i)DROP\s+TABLE\s+(IF\s+EXISTS\s+)?" + [regex]::Escape($core) + '\b') -Message "$name reset must not drop canonical core table $core."
        Assert-Absent -Text $text -Pattern ("(?i)(DELETE\s+FROM|TRUNCATE\s+TABLE)\s+" + [regex]::Escape($core) + '\b') -Message "$name reset must not empty canonical core table $core."
    }

    # 5) State reset uses an allowed status value and clears timestamps/errors.
    Assert-Present -Text $text -Pattern "(?i)Status\s*=\s*N'NotStarted'" -Message "$name reset must set its module state to NotStarted."
    Assert-Present -Text $text -Pattern '(?i)StartedAtUtc\s*=\s*NULL' -Message "$name reset must clear StartedAtUtc."
    Assert-Present -Text $text -Pattern '(?i)CompletedAtUtc\s*=\s*NULL' -Message "$name reset must clear CompletedAtUtc."
    Assert-Present -Text $text -Pattern '(?i)LastError\s*=\s*NULL' -Message "$name reset must clear LastError."

    # 6) State reset scope matches the dependency/staleness contract exactly.
    $match = [regex]::Match($text, '(?is)WHERE\s+ModuleNumber\s+IN\s*\(([^)]*)\)')
    if (-not $match.Success) {
        Add-Failure "$name reset must scope its state UPDATE with WHERE ModuleNumber IN (...)."
    }
    else {
        $found = @($match.Groups[1].Value -split ',' | ForEach-Object { ($_ -replace '[^0-9]', '') } | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
        $expected = @($expectedStateScope[$module] | Sort-Object -Unique)
        if (($found -join ',') -ne ($expected -join ',')) {
            Add-Failure "$name reset state scope is '$($found -join ',')' but must be '$($expected -join ',')'."
        }
    }
}

# M04 owns no persistent objects: it must not drop any object at all.
$m04 = Get-Text -Path (Join-Path $demoRoot 'M04\reset\reset.sql')
Assert-Absent -Text $m04 -Pattern '(?i)DROP\s+(TABLE|VIEW|PROCEDURE|FUNCTION|TRIGGER|INDEX|SECURITY\s+POLICY|USER|EXTERNAL\s+MODEL|FULLTEXT)' -Message 'M04 reset must not drop objects (M04 owns none).'

# M10 must remove the full-text index on the search corpus.
$m10 = Get-Text -Path (Join-Path $demoRoot 'M10\reset\reset.sql')
Assert-Present -Text $m10 -Pattern '(?i)DROP\s+FULLTEXT\s+INDEX\s+ON\s+search\.SearchDocuments' -Message 'M10 reset must drop the full-text index on search.SearchDocuments.'

# --- Full reset SQL asset -----------------------------------------------------
$sqlText = Get-Text -Path $fullResetSql
if ($null -ne $sqlText) {
    Assert-Present -Text $sqlText -Pattern '(?i)AdventureGearAI' -Message 'Full reset SQL asset must be hard-scoped to AdventureGearAI.'
    Assert-Present -Text $sqlText -Pattern '(?i)ALTER\s+DATABASE\s+\[AdventureGearAI\]\s+SET\s+SINGLE_USER\s+WITH\s+ROLLBACK\s+IMMEDIATE' -Message 'Full reset SQL asset must roll back active sessions before dropping.'
    Assert-Present -Text $sqlText -Pattern '(?i)DROP\s+DATABASE\s+\[AdventureGearAI\]' -Message 'Full reset SQL asset must drop the literal AdventureGearAI database.'
    Assert-Absent -Text $sqlText -Pattern 'DP800_M\d{2}' -Message 'Full reset SQL asset must never reference a legacy DP800_Mxx database.'
    # No dynamic destructive SQL.
    Assert-Absent -Text $sqlText -Pattern '(?is)(sp_executesql|EXEC(UTE)?\s*[\(@]).*(CREATE|ALTER|DROP|USE)\s+DATABASE' -Message 'Full reset SQL asset must not run dynamic destructive database SQL.'
    # Every ALTER/DROP DATABASE targets only the literal AdventureGearAI.
    foreach ($m in [regex]::Matches($sqlText, '(?im)^\s*(?<cmd>ALTER\s+DATABASE|DROP\s+DATABASE(?:\s+IF\s+EXISTS)?)\s+(?<target>\[[^\]\r\n]+\]|[^\s;\r\n]+)')) {
        $target = $m.Groups['target'].Value.Trim().Trim('[', ']')
        if ($target -ne 'AdventureGearAI') {
            Add-Failure "Full reset SQL asset targets '$target' for $($m.Groups['cmd'].Value); only AdventureGearAI is permitted."
        }
    }
}

# --- Repository-wide: only the approved asset may contain DROP DATABASE --------
$allResetFiles = @(Get-ChildItem -Path $demoRoot -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]reset[\\/]' })
$resolvedApprovedAsset = (Resolve-Path -LiteralPath $fullResetSql).Path
foreach ($file in $allResetFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if ($text -match '(?i)DROP\s+DATABASE') {
        if ((Resolve-Path -LiteralPath $file.FullName).Path -ne $resolvedApprovedAsset) {
            Add-Failure "Reset file $($file.FullName) contains DROP DATABASE but only reset-adventuregear.sql may."
        }
    }
}

# --- Full reset wrapper (AST hard-scoping) ------------------------------------
$wrapperText = Get-Text -Path $fullResetWrapper
if ($null -ne $wrapperText) {
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($fullResetWrapper, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($pe in $parseErrors) { Add-Failure "Full reset wrapper parse error at line $($pe.Extent.StartLineNumber): $($pe.Message)" }
    }

    # No arbitrary database parameter (only Server/User are exposed).
    $paramBlock = $ast.ParamBlock
    if ($null -ne $paramBlock) {
        foreach ($p in $paramBlock.Parameters) {
            $pName = $p.Name.VariablePath.UserPath
            Assert-True -Condition ($pName -notmatch '(?i)^Database$') -Message 'Full reset wrapper must not expose an arbitrary -Database parameter.'
        }
    }

    # Every -Database argument is the literal master or AdventureGearAI.
    $allowedTargets = @('master', 'AdventureGearAI')
    foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $elements = @($command.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            if ($el -isnot [System.Management.Automation.Language.CommandParameterAst] -or $el.ParameterName -ine 'Database') { continue }
            $arg = $el.Argument
            if ($null -eq $arg -and ($i + 1) -lt $elements.Count) { $arg = $elements[$i + 1] }
            if ($arg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                Add-Failure "Full reset wrapper -Database target must be a literal master/AdventureGearAI value. Found: $($arg.Extent.Text)"
            }
            elseif ($arg.Value -notin $allowedTargets) {
                Add-Failure "Full reset wrapper uses a forbidden database target: $($arg.Value)"
            }
        }
    }

    # References the literal reset SQL asset and re-runs the core bootstrap.
    Assert-Present -Text $wrapperText -Pattern "(?i)'reset-adventuregear\.sql'" -Message 'Full reset wrapper must reference the literal reset-adventuregear.sql asset.'
    Assert-Present -Text $wrapperText -Pattern '(?i)Invoke-Bootstrap\.ps1' -Message 'Full reset wrapper must re-run the core bootstrap to recreate AdventureGearAI.'
    # No -Modules delegation (avoid recursion into the module runner).
    Assert-Absent -Text $wrapperText -Pattern '(?i)-Modules\b' -Message 'Full reset wrapper must invoke the core bootstrap without -Modules (no recursion).'
    Assert-Absent -Text $wrapperText -Pattern '(?i)(PWD|PASSWORD)\s*=\s*[''"]?[^''";\s@$]' -Message 'Full reset wrapper must not embed a password literal.'
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all Task 6 reset static checks succeeded)' -ForegroundColor Green
exit 0
