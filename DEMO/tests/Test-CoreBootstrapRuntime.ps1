[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$bootstrapScript = Join-Path $repoRoot 'DEMO\bootstrap\Invoke-Bootstrap.ps1'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

# --- Preconditions: skip (do not fail) when the environment is unavailable ------
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Host 'SKIP: sqlcmd is not available.' -ForegroundColor Yellow
    exit 0
}
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Host 'SKIP: docker is not available.' -ForegroundColor Yellow
    exit 0
}
$running = (& docker ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
if (-not $running) {
    Write-Host "SKIP: container '$Container' is not running." -ForegroundColor Yellow
    exit 0
}

# --- Retrieve the SA password in-process from the container environment ---------
$password = (& docker exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Host "SKIP: MSSQL_SA_PASSWORD is not set in container '$Container'." -ForegroundColor Yellow
    exit 0
}

function Invoke-Query {
    param([string]$Database, [string]$Query)
    $result = & $sqlcmd.Source -S $Server -U $User -d $Database -Q $Query -h -1 -W -b -C 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd query failed against '$Database': $($result -join ' ')"
    }
    return @($result | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Get-DatabaseSet {
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Invoke-Query -Database 'master' -Query 'SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name;'),
        [System.StringComparer]::OrdinalIgnoreCase)
}

function Get-Scalar {
    param([string]$Database, [string]$Query)
    return (Invoke-Query -Database $Database -Query $Query | Select-Object -First 1)
}

function Assert-NativeJsonColumns {
    $nativeJsonColumns = [int](Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT COUNT(*)
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE ((c.object_id = OBJECT_ID(N'catalog.Products') AND c.name = N'ProductMetadata')
    OR (c.object_id = OBJECT_ID(N'customer.Customers') AND c.name = N'Preferences')
    OR (c.object_id = OBJECT_ID(N'sales.Orders') AND c.name = N'ShippingMetadata'))
  AND t.name = N'json'
  AND c.system_type_id = TYPE_ID(N'json')
  AND c.is_nullable = 1;
"@)
    if ($nativeJsonColumns -ne 3) {
        Add-Failure "Expected three nullable native json columns, but found $nativeJsonColumns."
    }
}

Write-Host 'Core bootstrap (AdventureGearAI) runtime integration test'
Write-Host ''

$expectedCounts = [ordered]@{
    'catalog.Categories'     = 10
    'catalog.Products'       = 150
    'catalog.Inventory'      = 150
    'customer.Customers'     = 120
    'customer.ProductReviews'= 500
    'sales.Orders'           = 800
    'sales.OrderItems'       = 2400
    'ops.DemoModuleState'    = 11
    'ops.DemoEnvironment'    = 1
}

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')

    # 1) Snapshot all existing database names.
    $before = Get-DatabaseSet
    Write-Host "Databases before bootstrap: $($before.Count)"

    # 2) Run bootstrap.
    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { Add-Failure 'First bootstrap run exited non-zero.' }

    # 3) Verify AdventureGearAI exists.
    $after = Get-DatabaseSet
    if (-not $after.Contains('AdventureGearAI')) {
        Add-Failure 'AdventureGearAI database was not created.'
    }

    # Schemas.
    $schemaCount = [int](Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.schemas WHERE name IN (N'catalog',N'sales',N'customer',N'security',N'ops',N'api',N'search',N'ai');")
    if ($schemaCount -ne 8) { Add-Failure "Expected 8 domain schemas but found $schemaCount." }

    # Marker structure/content.
    $markerDb = Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT DatabaseName FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1;"
    if ($markerDb -ne 'AdventureGearAI') { Add-Failure "ops.DemoEnvironment marker DatabaseName is '$markerDb'." }
    $markerVersion = Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT SchemaVersion FROM ops.DemoEnvironment WHERE DemoEnvironmentID = 1;"
    if ($markerVersion -ne '2.0.0-json170') { Add-Failure "ops.DemoEnvironment marker SchemaVersion is '$markerVersion' (expected '2.0.0-json170')." }

    # Module state structure: 11 rows numbered 1..11, all NotStarted with generated ModuleName.
    $moduleRange = Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT CONCAT(MIN(ModuleNumber), '-', MAX(ModuleNumber), '-', COUNT(*)) FROM ops.DemoModuleState;"
    if ($moduleRange -ne '1-11-11') { Add-Failure "ops.DemoModuleState range/count is '$moduleRange' (expected '1-11-11')." }
    $m01Name = Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT ModuleName FROM ops.DemoModuleState WHERE ModuleNumber = 1;"
    if ($m01Name -ne 'M01') { Add-Failure "ops.DemoModuleState computed ModuleName for module 1 is '$m01Name'." }

    # Core row counts.
    foreach ($table in $expectedCounts.Keys) {
        $actual = [int](Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM $table;")
        if ($actual -ne $expectedCounts[$table]) {
            Add-Failure "Row count for $table is $actual (expected $($expectedCounts[$table]))."
        }
    }

    Assert-NativeJsonColumns

    # Rich documents remain queryable through the JSON functions used in the
    # course and retain the canonical entities relied on by later modules.
    $jsonBehavior = Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(
    JSON_VALUE(CONVERT(nvarchar(max), p.ProductMetadata), N'$.terrain'), N'|',
    JSON_VALUE(CONVERT(nvarchar(max), c.Preferences), N'$.notifications.quietHours.start'), N'|',
    JSON_VALUE(CONVERT(nvarchar(max), o.ShippingMetadata), N'$.tracking.number'), N'|',
    (SELECT COUNT(*) FROM customer.ProductReviews WHERE ProductID = 4)
)
FROM catalog.Products AS p
CROSS JOIN customer.Customers AS c
CROSS JOIN sales.Orders AS o
WHERE p.ProductID = 1 AND c.CustomerID = 3 AND o.OrderID = 1;
"@
    if ($jsonBehavior -notmatch '^rocky trails\|21:00\|AG000001\|[2-9][0-9]*$') {
        Add-Failure "Native json documents did not preserve expected JSON behavior: '$jsonBehavior'."
    }
    $canonicalRows = Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT CONCAT(
    (SELECT ProductName FROM catalog.Products WHERE ProductID = 1), N'|',
    (SELECT ProductName FROM catalog.Products WHERE ProductID = 4), N'|',
    (SELECT CustomerName FROM customer.Customers WHERE CustomerID = 3)
);
"@
    if ($canonicalRows -ne 'Trailblazer 29 Bike|Puncture Guard Tire|Jordan Patel') {
        Add-Failure "Canonical seed rows changed: '$canonicalRows'."
    }

    # 4) Recreate the exact former nvarchar/check-constraint state, then prove
    # the bootstrap performs an in-place native-json migration without touching
    # any other database.
    Invoke-Query -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
ALTER TABLE catalog.Products ADD ProductMetadataLegacy nvarchar(max) NULL;
EXEC (N'UPDATE catalog.Products SET ProductMetadataLegacy = CONVERT(nvarchar(max), ProductMetadata);');
ALTER TABLE catalog.Products DROP COLUMN ProductMetadata;
EXEC sys.sp_rename N'catalog.Products.ProductMetadataLegacy', N'ProductMetadata', N'COLUMN';
ALTER TABLE catalog.Products ADD CONSTRAINT CK_Products_Metadata CHECK (ProductMetadata IS NULL OR ISJSON(ProductMetadata) = 1);
ALTER TABLE customer.Customers ADD PreferencesLegacy nvarchar(max) NULL;
EXEC (N'UPDATE customer.Customers SET PreferencesLegacy = CONVERT(nvarchar(max), Preferences);');
ALTER TABLE customer.Customers DROP COLUMN Preferences;
EXEC sys.sp_rename N'customer.Customers.PreferencesLegacy', N'Preferences', N'COLUMN';
ALTER TABLE customer.Customers ADD CONSTRAINT CK_Customers_Preferences CHECK (Preferences IS NULL OR ISJSON(Preferences) = 1);
ALTER TABLE sales.Orders ADD ShippingMetadataLegacy nvarchar(max) NULL;
EXEC (N'UPDATE sales.Orders SET ShippingMetadataLegacy = CONVERT(nvarchar(max), ShippingMetadata);');
ALTER TABLE sales.Orders DROP COLUMN ShippingMetadata;
EXEC sys.sp_rename N'sales.Orders.ShippingMetadataLegacy', N'ShippingMetadata', N'COLUMN';
ALTER TABLE sales.Orders ADD CONSTRAINT CK_Orders_ShippingMetadata CHECK (ShippingMetadata IS NULL OR ISJSON(ShippingMetadata) = 1);
UPDATE ops.DemoEnvironment SET SchemaVersion = N'1.0.0' WHERE DemoEnvironmentID = 1;
"@ | Out-Null

$legacyJsonColumns = [int](Get-Scalar -Database 'AdventureGearAI' -Query @"
SET NOCOUNT ON;
SELECT COUNT(*)
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE ((c.object_id = OBJECT_ID(N'catalog.Products') AND c.name = N'ProductMetadata')
    OR (c.object_id = OBJECT_ID(N'customer.Customers') AND c.name = N'Preferences')
    OR (c.object_id = OBJECT_ID(N'sales.Orders') AND c.name = N'ShippingMetadata'))
  AND t.name = N'json';
"@)
if ($legacyJsonColumns -ne 0) {
    Add-Failure "Legacy-state fixture retained $legacyJsonColumns native json columns instead of zero."
}

    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { Add-Failure 'Native-json migration bootstrap run exited non-zero.' }
    Assert-NativeJsonColumns

    # 5) Rerun again idempotently after the migration.
    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { Add-Failure 'Second post-migration (idempotent) bootstrap run exited non-zero.' }

    foreach ($table in $expectedCounts.Keys) {
        $actual = [int](Get-Scalar -Database 'AdventureGearAI' -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM $table;")
        if ($actual -ne $expectedCounts[$table]) {
            Add-Failure "After rerun, row count for $table is $actual (expected $($expectedCounts[$table])); bootstrap is not idempotent."
        }
    }

    # 6) Verify no other database was removed or added (only AdventureGearAI may differ).
    $afterRerun = Get-DatabaseSet
    $beforeOthers = @($before | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $afterOthers = @($afterRerun | Where-Object { $_ -ne 'AdventureGearAI' } | Sort-Object)
    $diff = Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers
    if ($diff) {
        Add-Failure "Databases other than AdventureGearAI changed: $(( $diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')"
    }
}
finally {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $originalDpPassword, 'Process')
    $password = $null
    [System.GC]::Collect()
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (runtime core bootstrap integration checks succeeded)' -ForegroundColor Green
exit 0
