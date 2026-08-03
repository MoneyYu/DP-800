[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$sourceHarnessPath = Join-Path $PSScriptRoot 'Test-UnifiedDemo.ps1'
$sandboxRoot = Join-Path $PSScriptRoot '.sandbox'

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

function Assert-Match {
    param(
        [string]$Actual,
        [string]$Pattern,
        [string]$Message
    )

    if ($Actual -notmatch $Pattern) {
        throw "$Message Pattern '$Pattern' was not found.`nActual output:`n$Actual"
    }
}

function Write-TestFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $Content -NoNewline
}

function Initialize-TestRepository {
    param([string]$Path)

    & git -C $Path init -q
    & git -C $Path config core.autocrlf false
    & git -C $Path config user.name 'Copilot Test'
    & git -C $Path config user.email 'copilot-test@example.com'
    & git -C $Path add .
    & git -C $Path commit -q -m 'fixture'
}

function New-MinimalUnifiedDemoRepository {
    param(
        [string]$Path,
        [string]$TopLevelReadme,
        [string]$BootstrapScript,
        [string]$FullResetScript
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    $demoRoot = Join-Path $Path 'DEMO'
    $bootstrapRoot = Join-Path $demoRoot 'bootstrap'
    $resetRoot = Join-Path $demoRoot 'reset'
    $m08CommonRoot = Join-Path $demoRoot 'M08\common'
    $publishRoot = Join-Path $demoRoot 'M07\common\Dp800.Database'
    $sharedRoot = Join-Path $demoRoot 'shared'
    $testsRoot = Join-Path $demoRoot 'tests'

    New-Item -ItemType Directory -Path $testsRoot -Force | Out-Null

    Write-TestFile -Path (Join-Path $demoRoot 'README.md') -Content $TopLevelReadme
    Write-TestFile -Path (Join-Path $bootstrapRoot 'Invoke-Bootstrap.ps1') -Content $BootstrapScript
    Write-TestFile -Path (Join-Path $bootstrapRoot '00-create-adventuregear-database.sql') -Content @'
PRINT N'AdventureGearAI';
CREATE DATABASE [AdventureGearAI];
'@
    Write-TestFile -Path (Join-Path $bootstrapRoot '01-initialize-adventuregear-demo.sql') -Content @'
USE [AdventureGearAI];
GO
PRINT N'AdventureGearAI';
'@
    Write-TestFile -Path (Join-Path $resetRoot 'Reset-AdventureGearAI.ps1') -Content $FullResetScript
    Write-TestFile -Path (Join-Path $m08CommonRoot 'dab-config.json') -Content @'
{
  "entities": {
    "Category": { "source": { "object": "api.Categories" } },
    "Product": { "source": { "object": "api.Products" } },
    "ProductCatalog": { "source": { "object": "api.ProductCatalog" } }
  }
}
'@
    Write-TestFile -Path (Join-Path $publishRoot 'DP800.publish.xml') -Content @'
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <PropertyGroup>
    <TargetDatabaseName>AdventureGearAI</TargetDatabaseName>
    <TargetConnectionString>Server=.;Database=AdventureGearAI;Trusted_Connection=True;</TargetConnectionString>
  </PropertyGroup>
</Project>
'@
    Write-TestFile -Path (Join-Path $sharedRoot 'ops.sql') -Content @'
CREATE SCHEMA ops;
GO
CREATE TABLE ops.DemoEnvironment (Id int);
GO
CREATE TABLE ops.DemoModuleState (Id int);
'@

    foreach ($moduleNumber in 1..11) {
        $moduleName = 'M{0:d2}' -f $moduleNumber
        $moduleRoot = Join-Path $demoRoot $moduleName
        Write-TestFile -Path (Join-Path $moduleRoot 'README.md') -Content @"
# $moduleName

Run `common/01-demo.sql` against `AdventureGearAI`.
"@
        Write-TestFile -Path (Join-Path $moduleRoot 'reset\reset.sql') -Content @'
PRINT N'reset module state';
'@
    }

    Copy-Item -LiteralPath $sourceHarnessPath -Destination (Join-Path $testsRoot 'Test-UnifiedDemo.ps1') -Force
    Initialize-TestRepository -Path $Path
}

function Invoke-HarnessFixture {
    param([string]$Name)

    $fixtureRoot = Join-Path $sandboxRoot $Name
    $harnessPath = Join-Path $fixtureRoot 'DEMO\tests\Test-UnifiedDemo.ps1'
    $output = & pwsh -NoProfile -File $harnessPath -BaseRef HEAD -HeadRef HEAD 2>&1 | Out-String

    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

try {
    if (Test-Path -LiteralPath $sandboxRoot) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
    }

    $topLevelReadmeFixture = Join-Path $sandboxRoot 'top-level-readme-target'
    New-MinimalUnifiedDemoRepository -Path $topLevelReadmeFixture -TopLevelReadme @'
# Demo

pwsh DEMO/scripts/Invoke-Dp800Sql.ps1 -Database DP800_M01 -InputFile DEMO/M01/common/01-demo.sql
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database AdventureGearAI -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
END
'@

    $topLevelReadmeResult = Invoke-HarnessFixture -Name 'top-level-readme-target'
    Assert-Equal -Actual $topLevelReadmeResult.ExitCode -Expected 1 -Message 'Harness should fail when DEMO\README.md still documents a DP800_Mxx execution target.'
    Assert-Match -Actual $topLevelReadmeResult.Output -Pattern 'DEMO\\README\.md' -Message 'Harness failure should point at the top-level README.'

    $legacyReportingFixture = Join-Path $sandboxRoot 'legacy-reporting-and-master'
    New-MinimalUnifiedDemoRepository -Path $legacyReportingFixture -TopLevelReadme @'
# Demo

Run `common/01-demo.sql` against `AdventureGearAI`.
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
Write-Host 'Legacy cleanup candidates such as DP800_M01 remain manual and non-automatic.'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database AdventureGearAI -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
Write-Host 'Legacy cleanup candidates such as DP800_M01 remain manual and non-automatic.'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
END

SELECT CASE
    WHEN DB_ID(N'DP800_M01') IS NOT NULL THEN N'legacy candidate'
    ELSE N'clean'
END;
'@

    $legacyReportingResult = Invoke-HarnessFixture -Name 'legacy-reporting-and-master'
    Assert-Equal -Actual $legacyReportingResult.ExitCode -Expected 0 -Message 'Harness should allow legacy reporting text and a master control connection when destructive targets stay hard-scoped.'

    $bootstrapSqlLegacyReportingFixture = Join-Path $sandboxRoot 'bootstrap-sql-legacy-reporting'
    New-MinimalUnifiedDemoRepository -Path $bootstrapSqlLegacyReportingFixture -TopLevelReadme @'
# Demo

Run `common/01-demo.sql` against `AdventureGearAI`.
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database AdventureGearAI -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
END
'@
    Write-TestFile -Path (Join-Path $bootstrapSqlLegacyReportingFixture 'DEMO\bootstrap\00-create-adventuregear-database.sql') -Content @'
PRINT N''AdventureGearAI bootstrap ready.'';
PRINT N''Legacy database DP800_M01 is a manual cleanup candidate only.'';
CREATE DATABASE [AdventureGearAI];
'@

    $bootstrapSqlLegacyReportingResult = Invoke-HarnessFixture -Name 'bootstrap-sql-legacy-reporting'
    Assert-Equal -Actual $bootstrapSqlLegacyReportingResult.ExitCode -Expected 0 -Message 'Harness should allow bootstrap SQL comments and PRINT statements that report DP800_Mxx cleanup candidates without targeting them.'

    $bootstrapSqlLegacyLoopFixture = Join-Path $sandboxRoot 'bootstrap-sql-legacy-loop'
    New-MinimalUnifiedDemoRepository -Path $bootstrapSqlLegacyLoopFixture -TopLevelReadme @'
# Demo

Run `common/01-demo.sql` against `AdventureGearAI`.
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database AdventureGearAI -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
END
'@
    Write-TestFile -Path (Join-Path $bootstrapSqlLegacyLoopFixture 'DEMO\bootstrap\00-create-adventuregear-database.sql') -Content @'
DECLARE @ModuleNumber int = 1;
DECLARE @DatabaseName sysname;

WHILE @ModuleNumber <= 11
BEGIN
    SET @DatabaseName = CONCAT(N''DP800_M'', RIGHT(CONCAT(N''0'', @ModuleNumber), 2));
    EXEC sys.sp_executesql N''CREATE DATABASE '' + QUOTENAME(@DatabaseName) + N'';'';
    SET @ModuleNumber += 1;
END;
'@

    $bootstrapSqlLegacyLoopResult = Invoke-HarnessFixture -Name 'bootstrap-sql-legacy-loop'
    Assert-Equal -Actual $bootstrapSqlLegacyLoopResult.ExitCode -Expected 1 -Message 'Harness should reject bootstrap SQL loops that construct legacy DP800_Mxx database names.'
    Assert-Match -Actual $bootstrapSqlLegacyLoopResult.Output -Pattern 'Bootstrap SQL asset.*legacy|DP800_M' -Message 'Harness failure should identify the bootstrap SQL legacy target pattern.'

    $dynamicDropFixture = Join-Path $sandboxRoot 'dynamic-drop-target'
    New-MinimalUnifiedDemoRepository -Path $dynamicDropFixture -TopLevelReadme @'
# Demo

Run `common/01-demo.sql` against `AdventureGearAI`.
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database AdventureGearAI -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
$databaseName = 'AdventureGearAI'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$databaseName];
END
'@

    $dynamicDropResult = Invoke-HarnessFixture -Name 'dynamic-drop-target'
    Assert-Equal -Actual $dynamicDropResult.ExitCode -Expected 1 -Message 'Harness should reject dynamic DROP/ALTER DATABASE targets.'
    Assert-Match -Actual $dynamicDropResult.Output -Pattern 'DROP DATABASE|ALTER DATABASE|hard-scoped|database target' -Message 'Harness failure should explain why a dynamic destructive target is forbidden.'

    $bootstrapVariableTargetFixture = Join-Path $sandboxRoot 'bootstrap-variable-database-target'
    New-MinimalUnifiedDemoRepository -Path $bootstrapVariableTargetFixture -TopLevelReadme @'
# Demo

Run `common/01-demo.sql` against `AdventureGearAI`.
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
$databaseName = 'AdventureGearAI'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database $databaseName -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
END
'@

    $bootstrapVariableTargetResult = Invoke-HarnessFixture -Name 'bootstrap-variable-database-target'
    Assert-Equal -Actual $bootstrapVariableTargetResult.ExitCode -Expected 1 -Message 'Harness should reject bootstrap database targets passed via variables, even when they currently resolve to AdventureGearAI.'
    Assert-Match -Actual $bootstrapVariableTargetResult.Output -Pattern 'Bootstrap script.*database target|non-literal|AdventureGearAI' -Message 'Harness failure should explain that bootstrap database targets must be literal master or AdventureGearAI values.'

    $bootstrapArbitraryTargetFixture = Join-Path $sandboxRoot 'bootstrap-arbitrary-database-target'
    New-MinimalUnifiedDemoRepository -Path $bootstrapArbitraryTargetFixture -TopLevelReadme @'
# Demo

Run `common/01-demo.sql` against `AdventureGearAI`.
'@ -BootstrapScript @'
$runner = Join-Path $PSScriptRoot '..\scripts\Invoke-Dp800Sql.ps1'
Write-Host 'Legacy cleanup candidates such as DP800_M01 remain manual and non-automatic.'
& $runner -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')
& $runner -Database ReportingSandbox -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')
'@ -FullResetScript @'
IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
END
'@

    $bootstrapArbitraryTargetResult = Invoke-HarnessFixture -Name 'bootstrap-arbitrary-database-target'
    Assert-Equal -Actual $bootstrapArbitraryTargetResult.ExitCode -Expected 1 -Message 'Harness should reject bootstrap execution targets outside master and AdventureGearAI.'
    Assert-Match -Actual $bootstrapArbitraryTargetResult.Output -Pattern 'Bootstrap script.*database target|Bootstrap script.*legacy' -Message 'Harness failure should identify the forbidden bootstrap database target.'
}
finally {
    if (Test-Path -LiteralPath $sandboxRoot) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
    }
}
