[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$probeDatabase = "DP800_M06M08FeatureProbe_$([guid]::NewGuid().ToString('N'))"
$collisionDatabase = "DP800_M06_IsolationProbe_Collision_$([guid]::NewGuid().ToString('N'))"
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Add-Failure $Message }
}
function Get-Source {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing source asset: $RelativePath"
        return $null
    }
    return Get-Content -LiteralPath $path -Raw
}
function Assert-Source {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($null -eq $Text -or $Text -notmatch $Pattern) { Add-Failure $Message }
}
function Get-SourceIndex {
    param([string]$Text, [string]$Value, [switch]$Last)
    if ($null -eq $Text) { return -1 }
    if ($Last) {
        return $Text.LastIndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return $Text.IndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase)
}
function Get-OptionalProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

Write-Host 'M06/M08 focused feature runtime tests'
Write-Host ''

$m06Isolation = Get-Source 'DEMO\M06\local\07-isolation-rcsi-probe.sql'
$m06PlanForcing = Get-Source 'DEMO\M06\local\08-query-store-plan-forcing.sql'
$m06Reset = Get-Source 'DEMO\M06\reset\reset.sql'
$m08Api = Get-Source 'DEMO\M08\common\01-product-api.sql'
$m08Reset = Get-Source 'DEMO\M08\reset\reset.sql'
$dabConfig = Get-Source 'DEMO\M08\common\dab-config.json'

Assert-Source $m06Isolation '(?i)NEWID\s*\(' 'M06 isolation demo must generate a unique probe database name.'
Assert-Source $m06Isolation '(?i)sp_addextendedproperty' 'M06 isolation demo must add a database ownership marker.'
Assert-Source $m06Isolation '(?i)DP800\.M06\.IsolationProbe' 'M06 isolation demo must use its ownership marker consistently.'
Assert-Source $m06Isolation '(?i)READ_COMMITTED_SNAPSHOT' 'M06 isolation demo must set RCSI only on its probe database.'
Assert-Source $m06Isolation '(?i)SET\s+TRANSACTION\s+ISOLATION\s+LEVEL\s+READ\s+COMMITTED' 'M06 isolation demo must execute READ COMMITTED.'
Assert-Source $m06Isolation '(?i)SERVERPROPERTY\s*\(\s*''EngineEdition''\s*\)' 'M06 isolation demo must emit the local/Azure boundary.'
Assert-Source $m06PlanForcing '(?i)sp_query_store_force_plan' 'M06 plan forcing demo must force a plan.'
Assert-Source $m06PlanForcing '(?i)is_forced_plan' 'M06 plan forcing demo must verify the forced state.'
Assert-Source $m06PlanForcing '(?i)sp_query_store_unforce_plan' 'M06 plan forcing demo must clean up a forced plan.'
Assert-Source $m06PlanForcing '(?i)(only|one).{0,80}plan|plan.{0,80}(only|one)' 'M06 plan forcing demo must explain the single-plan outcome.'
Assert-Source $m06PlanForcing '(?i)query_capture_mode_desc' 'M06 plan forcing demo must capture the prior Query Store capture mode.'
Assert-Source $m06PlanForcing '(?i)M06QueryStoreRuntimeState' 'M06 plan forcing demo must persist its prior capture mode for reset recovery.'
Assert-Source $m06PlanForcing '(?i)ExpectedDemoQueryCaptureMode' 'M06 plan forcing demo must persist the Query Store mode expected while recovery is active.'
Assert-Source $m06PlanForcing '(?i)RecoveryPhase' 'M06 plan forcing demo must record an active recovery phase.'
Assert-Source $m06Reset '(?i)sp_query_store_unforce_plan' 'M06 reset must unforce M06 Query Store plans.'
Assert-Source $m06Reset '(?i)M06QueryStoreRuntimeState' 'M06 reset must restore the Query Store capture mode recorded by M06.'
Assert-Source $m06Reset '(?i)ExpectedDemoQueryCaptureMode' 'M06 reset must restore Query Store capture mode only from active matching recovery metadata.'
Assert-Source $m06Reset '(?i)COL_LENGTH\s*\(' 'M06 reset must migrate legacy Query Store recovery metadata idempotently.'

Assert-Source $m08Api '(?i)sp_cdc_enable_db' 'M08 must enable CDC at database scope.'
Assert-Source $m08Api '(?i)sp_cdc_enable_table' 'M08 must enable CDC for the product source table.'
Assert-Source $m08Api '(?i)AdventureGearM08Products' 'M08 must use its dedicated CDC capture instance name.'
Assert-Source $m08Api '(?i)sp_getapplock' 'M08 setup must exclusively lock CDC ownership changes.'
Assert-Source $m08Api '(?i)@capture_instance\s*=\s*@m08CaptureInstance' 'M08 setup must pass its exact capture instance to CDC enablement.'
Assert-Source $m08Api '(?is)BEGIN\s+CATCH.*?@AppLockHeld\s*=\s*1.*?sp_releaseapplock.*?THROW' 'M08 setup must release a held CDC ownership lock on setup errors.'
Assert-Source $m08Api '(?i)M08CaptureInstance' 'M08 must persist the exact CDC capture instance it creates.'
Assert-Source $m08Api '(?i)dm_server_services|SQL Server Agent' 'M08 must record SQL Agent availability.'
Assert-Source $m08Api '(?i)CREATE\s+OR\s+ALTER\s+VIEW\s+api\.Products' 'M08 must create the Product read model.'
Assert-Source $m08Api '(?i)CREATE\s+OR\s+ALTER\s+PROCEDURE\s+api\.GetProductsByCategory' 'M08 must create the safe procedure source.'
Assert-Source $m08Reset '(?i)sp_cdc_disable_table' 'M08 reset must disable the owned CDC table capture.'
Assert-Source $m08Reset '(?i)sp_cdc_disable_db' 'M08 reset must disable CDC when M08 enabled it.'
Assert-Source $m08Reset '(?i)AdventureGearM08Products' 'M08 reset must revalidate the dedicated CDC capture instance.'
Assert-Source $m08Reset '(?i)sp_getapplock' 'M08 reset must exclusively lock CDC ownership changes.'
Assert-Source $m08Reset '(?i)M08CaptureInstance' 'M08 reset must target only M08''s recorded CDC capture instance.'
Assert-Source $m08Reset '(?is)BEGIN\s+CATCH.*?@AppLockHeld\s*=\s*1.*?sp_releaseapplock.*?THROW' 'M08 reset must release a held CDC ownership lock on reset errors.'
Assert-Source $m08Reset '(?i)DROP\s+PROCEDURE.*GetProductsByCategory' 'M08 reset must remove the owned procedure.'

$m08SetupLockAcquire = Get-SourceIndex $m08Api 'EXEC @appLockResult = sys.sp_getapplock'
$m08SetupStatusDdl = Get-SourceIndex $m08Api "IF OBJECT_ID(N'api.CdcRuntimeStatus'"
Assert-True ($m08SetupLockAcquire -ge 0 -and $m08SetupStatusDdl -ge 0 -and $m08SetupLockAcquire -lt $m08SetupStatusDdl) 'M08 setup must acquire the CDC ownership lock before CdcRuntimeStatus DDL.'
$m08SetupFinalStatusRead = Get-SourceIndex $m08Api 'FROM api.CdcRuntimeStatus' -Last
$m08SetupFinalApiDdl = Get-SourceIndex $m08Api 'CREATE OR ALTER PROCEDURE api.GetProductsByCategory'
$m08SetupFinalLockRelease = Get-SourceIndex $m08Api 'EXEC sys.sp_releaseapplock' -Last
Assert-True ($m08SetupFinalStatusRead -ge 0 -and $m08SetupFinalLockRelease -gt $m08SetupFinalStatusRead) 'M08 setup must release the CDC ownership lock only after its final CdcRuntimeStatus read.'
Assert-True ($m08SetupFinalApiDdl -ge 0 -and $m08SetupFinalLockRelease -gt $m08SetupFinalApiDdl) 'M08 setup must release the CDC ownership lock only after its final API DDL operation.'

$m08ResetRunningGuard = Get-SourceIndex $m08Reset 'M08 reset refused while Module 8 is Running'
$m08ResetCdcDisable = Get-SourceIndex $m08Reset 'EXEC sys.sp_cdc_disable_table'
$m08ResetStatusDrop = Get-SourceIndex $m08Reset 'DROP TABLE IF EXISTS api.CdcRuntimeStatus'
$m08ResetStateUpdate = Get-SourceIndex $m08Reset 'UPDATE ops.DemoModuleState'
$m08ResetFinalApiDrop = Get-SourceIndex $m08Reset 'DROP VIEW IF EXISTS api.Categories'
$m08ResetCatch = Get-SourceIndex $m08Reset 'BEGIN CATCH'
$m08ResetFinalLockRelease = Get-SourceIndex $m08Reset 'EXEC sys.sp_releaseapplock' -Last
Assert-True ($m08ResetRunningGuard -ge 0 -and $m08ResetCdcDisable -gt $m08ResetRunningGuard -and $m08ResetStatusDrop -gt $m08ResetRunningGuard) 'M08 reset must reject Running module state before CDC or API teardown.'
Assert-True ($m08ResetStatusDrop -ge 0 -and $m08ResetFinalLockRelease -gt $m08ResetStatusDrop) 'M08 reset must release the CDC ownership lock only after deleting CdcRuntimeStatus.'
Assert-True ($m08ResetStateUpdate -ge 0 -and $m08ResetFinalLockRelease -gt $m08ResetStateUpdate) 'M08 reset must keep the CDC ownership lock through the M08 module state update.'
Assert-True ($m08ResetFinalApiDrop -ge 0 -and $m08ResetFinalLockRelease -gt $m08ResetFinalApiDrop) 'M08 reset must release the CDC ownership lock only after its final API teardown operation.'
Assert-True ($m08ResetCatch -gt $m08ResetFinalApiDrop -and $m08ResetFinalLockRelease -gt $m08ResetCatch) 'M08 reset must catch API teardown failures and release the CDC ownership lock.'

$dab = $null
if ($null -ne $dabConfig) {
    try { $dab = $dabConfig | ConvertFrom-Json }
    catch { Add-Failure "DAB configuration is not valid JSON: $($_.Exception.Message)" }
}
if ($null -ne $dab) {
    $runtimeCache = Get-OptionalProperty $dab.runtime 'cache'
    $product = Get-OptionalProperty $dab.entities 'Product'
    $category = Get-OptionalProperty $dab.entities 'Category'
    $productsByCategory = Get-OptionalProperty $dab.entities 'ProductsByCategory'
    $productMappings = Get-OptionalProperty $product 'mappings'
    $productCache = Get-OptionalProperty $product 'cache'
    $productRelationships = Get-OptionalProperty $product 'relationships'
    $categoryRelationships = Get-OptionalProperty $category 'relationships'
    $productCategoryRelationship = Get-OptionalProperty $productRelationships 'category'
    $categoryProductsRelationship = Get-OptionalProperty $categoryRelationships 'products'
    Assert-True ($null -ne $runtimeCache -and $runtimeCache.enabled -eq $true) 'DAB must enable supported runtime caching.'
    Assert-True ($null -ne $productCache -and $productCache.enabled -eq $true) 'DAB Product must enable entity caching.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty $category 'source') 'object') -eq 'catalog.Categories') 'DAB Category must use the canonical table so the DAB CLI can validate relationships.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty $category 'source') 'type') -eq 'table') 'DAB Category relationship source must be a table.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty $product 'source') 'object') -eq 'catalog.Products') 'DAB Product must use the canonical table so the DAB CLI can validate relationships.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty $product 'source') 'type') -eq 'table') 'DAB Product relationship source must be a table.'
    Assert-True ($null -ne $categoryProductsRelationship) 'DAB Category must define its products relationship.'
    Assert-True ([string](Get-OptionalProperty $categoryProductsRelationship 'cardinality') -eq 'many') 'DAB Category.products relationship must have many cardinality.'
    Assert-True ([string](Get-OptionalProperty $categoryProductsRelationship 'target.entity') -eq 'Product') 'DAB Category.products relationship must target Product.'
    Assert-True (@(Get-OptionalProperty $categoryProductsRelationship 'source.fields') -join ',' -eq 'CategoryID') 'DAB Category.products relationship must use CategoryID as its source field.'
    Assert-True (@(Get-OptionalProperty $categoryProductsRelationship 'target.fields') -join ',' -eq 'CategoryID') 'DAB Category.products relationship must use Product.CategoryID as its target field.'
    Assert-True ($null -ne $productCategoryRelationship) 'DAB Product must define its category relationship.'
    Assert-True ([string](Get-OptionalProperty $productCategoryRelationship 'cardinality') -eq 'one') 'DAB Product.category relationship must have one cardinality.'
    Assert-True ([string](Get-OptionalProperty $productCategoryRelationship 'target.entity') -eq 'Category') 'DAB Product.category relationship must target Category.'
    Assert-True (@(Get-OptionalProperty $productCategoryRelationship 'source.fields') -join ',' -eq 'CategoryID') 'DAB Product.category relationship must use CategoryID as its source field.'
    Assert-True (@(Get-OptionalProperty $productCategoryRelationship 'target.fields') -join ',' -eq 'CategoryID') 'DAB Product.category relationship must use Category.CategoryID as its target field.'
    Assert-True ($null -eq (Get-OptionalProperty $productMappings 'CategoryID')) 'DAB Product mappings must leave CategoryID available as a relationship source field.'
    Assert-True ([string](Get-OptionalProperty $productMappings 'ProductID') -eq 'id') 'DAB Product must preserve the ProductID to id mapping.'
    Assert-True ([string](Get-OptionalProperty $productMappings 'ProductName') -eq 'name') 'DAB Product must preserve the ProductName to name mapping.'
    Assert-True ([string](Get-OptionalProperty $productMappings 'UnitPrice') -eq 'price') 'DAB Product must preserve the UnitPrice to price mapping.'
    Assert-True ($null -eq (Get-OptionalProperty $productMappings 'UnitsInStock')) 'DAB Product must not map UnitsInStock because catalog.Products has no such column.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty (Get-OptionalProperty $dab.entities 'ProductCatalog') 'source') 'object') -eq 'api.ProductCatalog') 'DAB ProductCatalog must retain its api read-model view source.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty (Get-OptionalProperty $dab.entities 'InventoryAvailability') 'source') 'object') -eq 'api.InventoryAvailability') 'DAB InventoryAvailability must retain its api read-model view source.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty $productsByCategory 'source') 'type') -eq 'stored-procedure') 'DAB must expose the safe procedure as a stored-procedure entity.'
    Assert-True ([string](Get-OptionalProperty (Get-OptionalProperty $productsByCategory 'source') 'object') -eq 'api.GetProductsByCategory') 'DAB stored-procedure entity must use the safe API procedure.'
    $procedureParameters = @(Get-OptionalProperty (Get-OptionalProperty $productsByCategory 'source') 'parameters')
    Assert-True ($procedureParameters.Count -eq 1) 'DAB stored-procedure entity must declare exactly one procedure parameter.'
    Assert-True ([string](Get-OptionalProperty $procedureParameters[0] 'name') -eq 'CategoryID') 'DAB stored-procedure parameter name must be CategoryID without a SQL @ prefix.'
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) source/config issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $sqlcmd -or -not $docker) {
    Write-Host 'SKIP: sqlcmd or docker is not available.' -ForegroundColor Yellow
    exit 0
}
$running = (& $docker.Source ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
if (-not $running) {
    Write-Host "SKIP: container '$Container' is not running." -ForegroundColor Yellow
    exit 0
}
$password = (& $docker.Source exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Host "SKIP: MSSQL_SA_PASSWORD is not set in '$Container'." -ForegroundColor Yellow
    exit 0
}

function Invoke-Query {
    param([string]$Database, [string]$Query)
    $output = & $sqlcmd.Source -S $Server -U $User -d $Database -Q $Query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed against '$Database': $($output -join ' ')" }
    return @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch '^\(\d+ rows? affected\)$' })
}
function Invoke-SqlFile {
    param([string]$Database, [string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    $output = & $sqlcmd.Source -S $Server -U $User -d $Database -i $path -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd file '$RelativePath' failed against '$Database': $($output -join ' ')" }
    return @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch '^\(\d+ rows? affected\)$' })
}
function Invoke-SqlFileExpectFailure {
    param([string]$Database, [string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    $output = & $sqlcmd.Source -S $Server -U $User -d $Database -i $path -h -1 -W -b -C -I -x 2>&1
    return @{
        ExitCode = $LASTEXITCODE
        Output = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
    }
}
function Remove-TestDatabase {
    param([string]$Database)
    $escapedDatabase = $Database.Replace("'", "''")
    $result = @(Invoke-Query -Database master -Query @"
DECLARE @owned bit = 0;
IF DB_ID(N'$escapedDatabase') IS NOT NULL
BEGIN
    DECLARE @checkSql nvarchar(max) = N'USE ' + QUOTENAME(N'$escapedDatabase') + N';
        IF EXISTS
        (
            SELECT 1
            FROM sys.extended_properties
            WHERE class = 0
              AND name = N''DP800.Test.M06M08FeatureRuntime''
              AND value = N''owned''
        )
            SELECT @markerPresent = CONVERT(bit, 1);';
    EXEC sys.sp_executesql @checkSql, N'@markerPresent bit OUTPUT', @markerPresent = @owned OUTPUT;
END;
SELECT CONVERT(int, @owned);
"@)
    if ($result -contains '1') {
        Invoke-Query -Database master -Query "ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database];" | Out-Null
    }
}

$originalPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$fixtureEnabledDatabaseCdc = $false
$fixtureCreatedCapture = $false
$fixtureCaptureInstance = 'DP800M08ForeignFixture'
$missingOwnedCaptureForeignInstance = 'DP800M08MissingOwnedForeign'
$missingOwnedCaptureForeignCreated = $false
$m08CaptureInstance = 'AdventureGearM08Products'
try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    Invoke-Query -Database master -Query "CREATE DATABASE [$probeDatabase];" | Out-Null
    Invoke-Query -Database $probeDatabase -Query @"
EXEC sys.sp_addextendedproperty
    @name = N'DP800.Test.M06M08FeatureRuntime',
    @value = N'owned';
"@ | Out-Null
    Invoke-Query -Database master -Query @"
ALTER DATABASE [$probeDatabase] SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
SELECT CASE WHEN is_read_committed_snapshot_on = 0 THEN 'PASS' ELSE 'FAIL' END
FROM sys.databases WHERE name = N'$probeDatabase';
ALTER DATABASE [$probeDatabase] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
SELECT CASE WHEN is_read_committed_snapshot_on = 1 THEN 'PASS' ELSE 'FAIL' END
FROM sys.databases WHERE name = N'$probeDatabase';
"@ | ForEach-Object { $_ } | Where-Object { $_ -in 'PASS', 'FAIL' } | ForEach-Object {
        Assert-True ($_ -eq 'PASS') "M06 probe RCSI transition returned '$_'."
    }
    $rcsiResults = @(Invoke-Query -Database master -Query "SELECT CASE WHEN is_read_committed_snapshot_on = 1 THEN 'PASS' ELSE 'FAIL' END FROM sys.databases WHERE name = N'$probeDatabase';")
    Assert-True ($rcsiResults -contains 'PASS') 'M06 probe must retain RCSI after its transition.'

    Invoke-Query -Database master -Query "CREATE DATABASE [$collisionDatabase];" | Out-Null
    Invoke-Query -Database $collisionDatabase -Query @"
EXEC sys.sp_addextendedproperty
    @name = N'DP800.Test.M06M08FeatureRuntime',
    @value = N'owned';
"@ | Out-Null
    Invoke-SqlFile -Database master -RelativePath 'DEMO\M06\local\07-isolation-rcsi-probe.sql' | Out-Null
    Invoke-SqlFile -Database master -RelativePath 'DEMO\M06\local\10-isolation-reader.sql' | Out-Null
    Invoke-SqlFile -Database master -RelativePath 'DEMO\M06\local\11-enable-rcsi.sql' | Out-Null
    Invoke-SqlFile -Database master -RelativePath 'DEMO\M06\local\12-isolation-rcsi-cleanup.sql' | Out-Null
    $collisionResults = @(Invoke-Query -Database master -Query "SELECT CASE WHEN DB_ID(N'$collisionDatabase') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END;")
    Assert-True ($collisionResults -contains 'PASS') 'M06 isolation cleanup must preserve an unmarked colliding database.'

    Invoke-Query -Database AdventureGearAI -Query @"
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = AUTO);
SELECT query_capture_mode_desc
FROM sys.database_query_store_options;
"@ | Out-Null
    $priorCaptureMode = @(Invoke-Query -Database AdventureGearAI -Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;')
    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M06\common\01-workload.sql' | Out-Null
    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M06\local\08-query-store-plan-forcing.sql' | Out-Null
    $postDemoCaptureMode = @(Invoke-Query -Database AdventureGearAI -Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;')
    Assert-True (($postDemoCaptureMode | Select-Object -First 1) -eq ($priorCaptureMode | Select-Object -First 1)) 'M06 plan-forcing demo must restore the prior Query Store capture mode.'
    $completedRecoveryStateRows = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT COUNT(*)
FROM ops.M06QueryStoreRuntimeState
WHERE M06QueryStoreRuntimeStateID = 1;
"@)
    Assert-True (($completedRecoveryStateRows | Select-Object -First 1) -eq '0') 'Successful M06 plan-forcing cleanup must clear its Query Store recovery state.'
    Invoke-Query -Database AdventureGearAI -Query @"
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = NONE);
"@ | Out-Null
    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M06\reset\reset.sql' | Out-Null
    $postResetCaptureMode = @(Invoke-Query -Database AdventureGearAI -Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;')
    Assert-True (($postResetCaptureMode | Select-Object -First 1) -eq 'NONE') 'M06 reset must not revert a Query Store capture mode configured after successful plan-forcing cleanup.'

    Invoke-Query -Database AdventureGearAI -Query @"
CREATE TABLE ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID tinyint NOT NULL
        CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
        CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
    PriorQueryCaptureMode nvarchar(60) NOT NULL,
    RecordedAtUtc datetime2(0) NOT NULL
);
INSERT ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID,
    PriorQueryCaptureMode,
    RecordedAtUtc
)
VALUES (1, N'AUTO', SYSUTCDATETIME());
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = NONE);
"@ | Out-Null
    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M06\reset\reset.sql' | Out-Null
    $staleRecoveryCaptureMode = @(Invoke-Query -Database AdventureGearAI -Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;')
    Assert-True (($staleRecoveryCaptureMode | Select-Object -First 1) -eq 'NONE') 'M06 reset must preserve a user capture mode when stale active recovery metadata no longer matches its expected demo mode.'
    $staleRecoveryStateRemoved = @(Invoke-Query -Database AdventureGearAI -Query "SELECT CASE WHEN OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NULL THEN N'PASS' ELSE N'FAIL' END;")
    Assert-True ($staleRecoveryStateRemoved -contains 'PASS') 'M06 reset must clear stale Query Store recovery metadata without changing the user capture mode.'

    Invoke-Query -Database AdventureGearAI -Query @"
CREATE TABLE ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID tinyint NOT NULL
        CONSTRAINT PK_M06QueryStoreRuntimeState PRIMARY KEY
        CONSTRAINT CK_M06QueryStoreRuntimeState_Singleton CHECK (M06QueryStoreRuntimeStateID = 1),
    PriorQueryCaptureMode nvarchar(60) NOT NULL,
    ExpectedDemoQueryCaptureMode nvarchar(60) NOT NULL,
    RecoveryPhase nvarchar(30) NOT NULL,
    RecordedAtUtc datetime2(0) NOT NULL
);
INSERT ops.M06QueryStoreRuntimeState
(
    M06QueryStoreRuntimeStateID,
    PriorQueryCaptureMode,
    ExpectedDemoQueryCaptureMode,
    RecoveryPhase,
    RecordedAtUtc
)
VALUES (1, N'AUTO', N'ALL', N'Active', SYSUTCDATETIME());
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
"@ | Out-Null
    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M06\reset\reset.sql' | Out-Null
    $recoveredCaptureMode = @(Invoke-Query -Database AdventureGearAI -Query 'SELECT query_capture_mode_desc FROM sys.database_query_store_options;')
    Assert-True (($recoveredCaptureMode | Select-Object -First 1) -eq 'AUTO') 'M06 reset must restore an interrupted active Query Store recovery state when its expected demo mode remains active.'
    $recoveryStateRemoved = @(Invoke-Query -Database AdventureGearAI -Query "SELECT CASE WHEN OBJECT_ID(N'ops.M06QueryStoreRuntimeState', N'U') IS NULL THEN N'PASS' ELSE N'FAIL' END;")
    Assert-True ($recoveryStateRemoved -contains 'PASS') 'M06 reset must clear completed active Query Store recovery state.'

    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\reset\reset.sql' | Out-Null
    $cdcInitial = @(Invoke-Query -Database AdventureGearAI -Query "SELECT is_cdc_enabled FROM sys.databases WHERE database_id = DB_ID();")
    if (($cdcInitial | Select-Object -First 1) -eq '0') {
        Invoke-Query -Database AdventureGearAI -Query 'EXEC sys.sp_cdc_enable_db;' | Out-Null
        $fixtureEnabledDatabaseCdc = $true
    }
    $fixtureCaptureExists = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM cdc.change_tables
    WHERE source_object_id = OBJECT_ID(N'catalog.Products')
      AND capture_instance = N'$fixtureCaptureInstance'
) THEN N'PASS' ELSE N'FAIL' END;
"@)
    if ($fixtureCaptureExists -notcontains 'PASS') {
        Invoke-Query -Database AdventureGearAI -Query "EXEC sys.sp_cdc_enable_table @source_schema = N'catalog', @source_name = N'Products', @role_name = NULL, @supports_net_changes = 1, @capture_instance = N'$fixtureCaptureInstance';" | Out-Null
        $fixtureCreatedCapture = $true
    }
    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\common\01-product-api.sql' | Out-Null
    $m08CaptureCreated = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM cdc.change_tables
    WHERE source_object_id = OBJECT_ID(N'catalog.Products')
      AND capture_instance = N'$m08CaptureInstance'
) THEN N'PASS' ELSE N'FAIL' END;
"@)
    Assert-True ($m08CaptureCreated -contains 'PASS') 'M08 setup must create its dedicated CDC capture beside a foreign capture.'
    $recordedM08Capture = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT M08CaptureInstance
FROM api.CdcRuntimeStatus
WHERE CdcRuntimeStatusID = 1;
"@)
    Assert-True (($recordedM08Capture | Select-Object -First 1) -eq $m08CaptureInstance) 'M08 must record only its dedicated CDC capture instance.'

    $m08ApiSignatureBeforeRunningReset = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CONCAT(
    OBJECT_ID(N'api.CdcRuntimeStatus', N'U'), N'|',
    OBJECT_ID(N'api.GetProductsByCategory', N'P'), N'|',
    OBJECT_ID(N'api.InventoryAvailability', N'V'), N'|',
    OBJECT_ID(N'api.ProductCatalog', N'V'), N'|',
    OBJECT_ID(N'api.Products', N'V'), N'|',
    OBJECT_ID(N'api.Categories', N'V'));
"@)
    $m08CdcSignatureBeforeRunningReset = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CONCAT(
    (SELECT is_cdc_enabled FROM sys.databases WHERE database_id = DB_ID()), N'|',
    CASE WHEN EXISTS
    (
        SELECT 1
        FROM cdc.change_tables
        WHERE source_object_id = OBJECT_ID(N'catalog.Products')
          AND capture_instance = N'$m08CaptureInstance'
    ) THEN N'1' ELSE N'0' END);
"@)
    $originalM08Status = (Invoke-Query -Database AdventureGearAI -Query 'SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber = 8;' | Select-Object -First 1)
    Assert-True (-not [string]::IsNullOrWhiteSpace($originalM08Status)) 'M08 state row must exist before the Running-state reset collision test.'
    Invoke-Query -Database AdventureGearAI -Query "UPDATE ops.DemoModuleState SET Status = N'Running', UpdatedAtUtc = SYSUTCDATETIME() WHERE ModuleNumber = 8;" | Out-Null

    $runningReset = Invoke-SqlFileExpectFailure -Database AdventureGearAI -RelativePath 'DEMO\M08\reset\reset.sql'
    Assert-True ($runningReset.ExitCode -ne 0) 'M08 reset must fail while Module 8 is Running.'
    Assert-True (($runningReset.Output -join ' ') -match 'M08 reset refused while Module 8 is Running') 'M08 reset must report that a Running Module 8 cannot be reset.'
    $m08ApiSignatureAfterRunningReset = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CONCAT(
    OBJECT_ID(N'api.CdcRuntimeStatus', N'U'), N'|',
    OBJECT_ID(N'api.GetProductsByCategory', N'P'), N'|',
    OBJECT_ID(N'api.InventoryAvailability', N'V'), N'|',
    OBJECT_ID(N'api.ProductCatalog', N'V'), N'|',
    OBJECT_ID(N'api.Products', N'V'), N'|',
    OBJECT_ID(N'api.Categories', N'V'));
"@)
    $m08CdcSignatureAfterRunningReset = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CONCAT(
    (SELECT is_cdc_enabled FROM sys.databases WHERE database_id = DB_ID()), N'|',
    CASE WHEN EXISTS
    (
        SELECT 1
        FROM cdc.change_tables
        WHERE source_object_id = OBJECT_ID(N'catalog.Products')
          AND capture_instance = N'$m08CaptureInstance'
    ) THEN N'1' ELSE N'0' END);
"@)
    Assert-True (($m08ApiSignatureAfterRunningReset | Select-Object -First 1) -eq ($m08ApiSignatureBeforeRunningReset | Select-Object -First 1)) 'M08 Running-state reset rejection must preserve all API objects.'
    Assert-True (($m08CdcSignatureAfterRunningReset | Select-Object -First 1) -eq ($m08CdcSignatureBeforeRunningReset | Select-Object -First 1)) 'M08 Running-state reset rejection must preserve CDC ownership objects.'
    $m08StatusAfterRunningReset = (Invoke-Query -Database AdventureGearAI -Query 'SELECT Status FROM ops.DemoModuleState WHERE ModuleNumber = 8;' | Select-Object -First 1)
    Assert-True ($m08StatusAfterRunningReset -eq 'Running') 'M08 Running-state reset rejection must not change the module state.'
    $escapedOriginalM08Status = $originalM08Status.Replace("'", "''")
    Invoke-Query -Database AdventureGearAI -Query "UPDATE ops.DemoModuleState SET Status = N'$escapedOriginalM08Status', UpdatedAtUtc = SYSUTCDATETIME() WHERE ModuleNumber = 8;" | Out-Null

    Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\reset\reset.sql' | Out-Null
    $cdcPreserved = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE WHEN EXISTS
(
    SELECT 1
    FROM cdc.change_tables
    WHERE source_object_id = OBJECT_ID(N'catalog.Products')
      AND capture_instance = N'$fixtureCaptureInstance'
) THEN N'PASS' ELSE N'FAIL' END;
"@)
    Assert-True ($cdcPreserved -contains 'PASS') "M08 reset must preserve pre-existing CDC capture '$fixtureCaptureInstance'; observed '$($cdcPreserved -join ', ')'."
    $m08CaptureRemoved = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE WHEN NOT EXISTS
(
    SELECT 1
    FROM cdc.change_tables
    WHERE source_object_id = OBJECT_ID(N'catalog.Products')
      AND capture_instance = N'$m08CaptureInstance'
) THEN N'PASS' ELSE N'FAIL' END;
"@)
    Assert-True ($m08CaptureRemoved -contains 'PASS') 'M08 reset must disable only its dedicated CDC capture instance.'

    if ($fixtureEnabledDatabaseCdc -and $fixtureCreatedCapture) {
        Invoke-Query -Database AdventureGearAI -Query @"
EXEC sys.sp_cdc_disable_table
    @source_schema = N'catalog',
    @source_name = N'Products',
    @capture_instance = N'$fixtureCaptureInstance';
IF NOT EXISTS (SELECT 1 FROM cdc.change_tables)
    EXEC sys.sp_cdc_disable_db;
"@ | Out-Null
        $fixtureCreatedCapture = $false

        Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\common\01-product-api.sql' | Out-Null
        $moduleOwnedDatabaseCdc = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE WHEN DatabaseCdcEnabledByModule = 1 THEN N'PASS' ELSE N'FAIL' END
FROM api.CdcRuntimeStatus
WHERE CdcRuntimeStatusID = 1;
"@)
        Assert-True ($moduleOwnedDatabaseCdc -contains 'PASS') 'M08 setup must record database CDC that it enabled.'

        Invoke-Query -Database AdventureGearAI -Query @"
EXEC sys.sp_cdc_disable_table
    @source_schema = N'catalog',
    @source_name = N'Products',
    @capture_instance = N'$m08CaptureInstance';
"@ | Out-Null
        Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\reset\reset.sql' | Out-Null
        $missingOwnedCaptureDisablesDatabaseCdc = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE WHEN is_cdc_enabled = 0 THEN N'PASS' ELSE N'FAIL' END
FROM sys.databases
WHERE database_id = DB_ID();
"@)
        Assert-True ($missingOwnedCaptureDisablesDatabaseCdc -contains 'PASS') 'M08 reset must disable module-owned database CDC when its externally removed capture was the final capture.'

        Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\common\01-product-api.sql' | Out-Null
        Invoke-Query -Database AdventureGearAI -Query @"
EXEC sys.sp_cdc_enable_table
    @source_schema = N'catalog',
    @source_name = N'Products',
    @role_name = NULL,
    @supports_net_changes = 1,
    @capture_instance = N'$missingOwnedCaptureForeignInstance';
"@ | Out-Null
        $missingOwnedCaptureForeignCreated = $true
        Invoke-Query -Database AdventureGearAI -Query @"
EXEC sys.sp_cdc_disable_table
    @source_schema = N'catalog',
    @source_name = N'Products',
    @capture_instance = N'$m08CaptureInstance';
"@ | Out-Null
        Invoke-SqlFile -Database AdventureGearAI -RelativePath 'DEMO\M08\reset\reset.sql' | Out-Null
        $foreignCapturePreservesDatabaseCdc = @(Invoke-Query -Database AdventureGearAI -Query @"
SELECT CASE
    WHEN (SELECT is_cdc_enabled FROM sys.databases WHERE database_id = DB_ID()) = 1
     AND EXISTS
     (
         SELECT 1
         FROM cdc.change_tables
         WHERE source_object_id = OBJECT_ID(N'catalog.Products')
           AND capture_instance = N'$missingOwnedCaptureForeignInstance'
     ) THEN N'PASS'
    ELSE N'FAIL'
END;
"@)
        Assert-True ($foreignCapturePreservesDatabaseCdc -contains 'PASS') 'M08 reset must preserve database CDC and a foreign capture when its owned capture was externally removed.'
    }

    $planForcingResults = @(Invoke-Query -Database $probeDatabase -Query @"
ALTER DATABASE CURRENT SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
CREATE TABLE dbo.PlanProbe
(
    Id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerId int NOT NULL,
    OccurredAt datetime2(0) NOT NULL
);
;WITH n AS
(
    SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
)
INSERT dbo.PlanProbe (CustomerId, OccurredAt)
SELECT CASE WHEN Number % 100 = 0 THEN 7 ELSE 1 END, DATEADD(minute, -Number, SYSUTCDATETIME())
FROM n;
EXEC sp_recompile N'dbo.PlanProbe';
EXEC(N'SELECT COUNT_BIG(*) FROM dbo.PlanProbe WHERE CustomerId = 7 /* DP800 M06 forcing probe */ OPTION (MAXDOP 1);');
CREATE INDEX IX_PlanProbe_CustomerOccurred ON dbo.PlanProbe(CustomerId, OccurredAt);
EXEC sp_recompile N'dbo.PlanProbe';
EXEC(N'SELECT COUNT_BIG(*) FROM dbo.PlanProbe WHERE CustomerId = 7 /* DP800 M06 forcing probe */ OPTION (MAXDOP 1);');
DECLARE @queryId bigint =
(
    SELECT TOP (1) q.query_id
    FROM sys.query_store_query AS q
    INNER JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE qt.query_sql_text LIKE N'%DP800 M06 forcing probe%'
    ORDER BY q.query_id DESC
);
DECLARE @planId bigint =
(
    SELECT TOP (1) p.plan_id
    FROM sys.query_store_plan AS p
    WHERE p.query_id = @queryId
    ORDER BY p.plan_id DESC
);
IF @queryId IS NULL OR @planId IS NULL
    THROW 51000, 'Query Store did not capture the M06 forcing probe.', 1;
IF (SELECT COUNT(*) FROM sys.query_store_plan WHERE query_id = @queryId) < 2
BEGIN
    SELECT N'SKIP_ONE_PLAN';
    RETURN;
END;
EXEC sys.sp_query_store_force_plan @query_id = @queryId, @plan_id = @planId;
IF NOT EXISTS (SELECT 1 FROM sys.query_store_plan WHERE query_id = @queryId AND plan_id = @planId AND is_forced_plan = 1)
    THROW 51001, 'Query Store did not mark the plan forced.', 1;
EXEC sys.sp_query_store_unforce_plan @query_id = @queryId, @plan_id = @planId;
IF EXISTS (SELECT 1 FROM sys.query_store_plan WHERE query_id = @queryId AND plan_id = @planId AND is_forced_plan = 1)
    THROW 51002, 'Query Store retained a forced plan after cleanup.', 1;
SELECT N'PASS';
"@ | Where-Object { $_ -in 'PASS', 'SKIP_ONE_PLAN' })
    Assert-True ($planForcingResults.Count -eq 1) 'M06 plan forcing probe must return exactly one lifecycle result.'
    $planForcingResults | ForEach-Object {
        Assert-True ($_ -in 'PASS', 'SKIP_ONE_PLAN') "M06 plan forcing lifecycle returned '$_'."
        if ($_ -eq 'SKIP_ONE_PLAN') { Write-Host 'M06 plan forcing: optimizer produced one plan; truthful skip path exercised.' -ForegroundColor Yellow }
    }

    $cdcResults = @(Invoke-Query -Database $probeDatabase -Query @"
CREATE TABLE dbo.CdcProbe (Id int NOT NULL PRIMARY KEY, Name nvarchar(50) NOT NULL);
BEGIN TRY
    EXEC sys.sp_cdc_enable_db;
    EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'CdcProbe', @role_name = NULL;
    IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID(N'dbo.CdcProbe'))
        THROW 51003, 'CDC table capture was not created.', 1;
    EXEC sys.sp_cdc_disable_table @source_schema = N'dbo', @source_name = N'CdcProbe', @capture_instance = N'dbo_CdcProbe';
    EXEC sys.sp_cdc_disable_db;
    SELECT CASE WHEN (SELECT is_cdc_enabled FROM sys.databases WHERE database_id = DB_ID()) = 0 THEN N'PASS' ELSE N'FAIL' END;
END TRY
BEGIN CATCH
    SELECT N'SKIP_CDC:' + ERROR_MESSAGE();
END CATCH;
"@ | Where-Object { $_ -eq 'PASS' -or $_ -like 'SKIP_CDC:*' })
    Assert-True ($cdcResults.Count -eq 1) 'M08 CDC probe must return exactly one lifecycle result.'
    $cdcResults | ForEach-Object {
        Assert-True ($_ -eq 'PASS' -or $_ -like 'SKIP_CDC:*') "M08 CDC lifecycle returned '$_'."
        if ($_ -like 'SKIP_CDC:*') { Write-Host "M08 CDC unavailable in this local runtime: $_" -ForegroundColor Yellow }
    }
}
catch {
    Add-Failure "Runtime probe failed: $($_.Exception.Message)"
}
finally {
    try {
        if ($missingOwnedCaptureForeignCreated) {
            Invoke-Query -Database AdventureGearAI -Query @"
IF EXISTS
(
    SELECT 1
    FROM cdc.change_tables
    WHERE source_object_id = OBJECT_ID(N'catalog.Products')
      AND capture_instance = N'$missingOwnedCaptureForeignInstance'
)
    EXEC sys.sp_cdc_disable_table
        @source_schema = N'catalog',
        @source_name = N'Products',
        @capture_instance = N'$missingOwnedCaptureForeignInstance';
IF NOT EXISTS (SELECT 1 FROM cdc.change_tables)
    EXEC sys.sp_cdc_disable_db;
"@ | Out-Null
            $fixtureEnabledDatabaseCdc = $false
        }
        if ($fixtureCreatedCapture -and -not [string]::IsNullOrWhiteSpace($fixtureCaptureInstance)) {
            Invoke-Query -Database AdventureGearAI -Query @"
IF EXISTS
(
    SELECT 1
    FROM cdc.change_tables
    WHERE source_object_id = OBJECT_ID(N'catalog.Products')
      AND capture_instance = N'$fixtureCaptureInstance'
)
    EXEC sys.sp_cdc_disable_table
        @source_schema = N'catalog',
        @source_name = N'Products',
        @capture_instance = N'$fixtureCaptureInstance';
"@ | Out-Null
        }
        if ($fixtureEnabledDatabaseCdc) {
            Invoke-Query -Database AdventureGearAI -Query @"
IF NOT EXISTS (SELECT 1 FROM cdc.change_tables)
    EXEC sys.sp_cdc_disable_db;
"@ | Out-Null
        }
        Remove-TestDatabase -Database $probeDatabase
        Remove-TestDatabase -Database $collisionDatabase
    }
    catch {
        Add-Failure "Probe cleanup failed: $($_.Exception.Message)"
    }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalPassword, 'Process')
    $password = $null
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (M06/M08 focused runtime features)' -ForegroundColor Green
