[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Database = 'AdventureGearAI',
    [int[]]$Modules = @()
)

$ErrorActionPreference = 'Stop'

# The unified demo provisions exactly one database, literally named
# AdventureGearAI. The -Database parameter is preserved for interface
# compatibility but must resolve to that single supported target.
if ($Database -ne 'AdventureGearAI') {
    throw "The unified demo provisions only the AdventureGearAI database; '$Database' is not a supported target."
}

# A per-module runner handles module execution. When modules are requested we
# initialize the core below and then delegate to Invoke-DemoModule.ps1. The
# runner invokes this bootstrap without -Modules to ensure the core, so there is
# no recursion.
$demoRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $demoRoot 'scripts\Invoke-Dp800Sql.ps1'
$moduleRunner = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'

Write-Host 'Provisioning the AdventureGearAI unified demo database...'

# 1) Create the single AdventureGearAI database from master (idempotent).
& $runner -Server $Server -User $User -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')

# 2) Initialize schemas, operational tracking, and the ecommerce core inside
#    AdventureGearAI (idempotent). This trusted bootstrap path creates the very
#    marker the database guard checks, so the guard is intentionally skipped.
& $runner -Server $Server -User $User -Database AdventureGearAI -SkipDatabaseGuard -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')

# 3) Report (never drop) any legacy DP800_Mxx databases as manual cleanup candidates.
Write-Host 'Checking for legacy per-module databases (reported as manual cleanup candidates only; never dropped automatically)...'
& $runner -Server $Server -User $User -Database master -InputFile (Join-Path $PSScriptRoot 'report-legacy-databases.sql')

Write-Host 'AdventureGearAI core bootstrap complete.'

# 4) When modules are requested, delegate to the dependency-aware runner after
#    the core exists. -SkipCoreBootstrap prevents the runner from re-invoking
#    this bootstrap (the core was just provisioned above).
#
#    The runner is dot-sourced into the current process so that the [int[]]
#    $Modules array is passed intact — spawning a child pwsh -File process
#    causes multi-element arrays to be serialized/concatenated and lose values.
#
#    IMPORTANT: dot-sourcing $moduleRunner re-executes that script's param()
#    block in THIS scope. Because we dot-source without arguments, every runner
#    parameter (-Modules, -Server, -User, -Database, -Force, ...) is reassigned
#    to the runner's own DEFAULTS, silently clobbering this bootstrap's $Server,
#    $User, and $Modules. To prevent that, capture the caller's values in
#    uniquely named variables BEFORE the dot-source and invoke the runner with
#    those captured copies only. -Database is intentionally not forwarded: it is
#    already guarded to AdventureGearAI above and the runner defaults to it, so
#    forwarding a (captured) variable would also violate the literal-target rule.
if ($Modules.Count -gt 0) {
    $bootstrapRequestedModules = @($Modules)
    $bootstrapServer = $Server
    $bootstrapUser = $User

    Write-Host "Delegating module execution to the runner for: $((@($bootstrapRequestedModules) | ForEach-Object { 'M{0:d2}' -f $_ }) -join ', ')"
    . $moduleRunner
    Invoke-DemoModuleRunner -Server $bootstrapServer -User $bootstrapUser -Modules $bootstrapRequestedModules -SkipCoreBootstrap
}
