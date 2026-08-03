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

# A per-module runner is not available yet in this task. Fail explicitly when
# module execution is requested so the contract is clear for the later runner.
if ($Modules.Count -gt 0) {
    throw "Modules were requested ($($Modules -join ', ')), but the per-module runner is not available yet. Re-run without -Modules to provision the AdventureGearAI core; module execution is wired in a later task."
}

$demoRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $demoRoot 'scripts\Invoke-Dp800Sql.ps1'

Write-Host 'Provisioning the AdventureGearAI unified demo database...'

# 1) Create the single AdventureGearAI database from master (idempotent).
& $runner -Server $Server -User $User -Database master -InputFile (Join-Path $PSScriptRoot '00-create-adventuregear-database.sql')

# 2) Initialize schemas, operational tracking, and the ecommerce core inside AdventureGearAI (idempotent).
& $runner -Server $Server -User $User -Database AdventureGearAI -InputFile (Join-Path $PSScriptRoot '01-initialize-adventuregear-demo.sql')

# 3) Report (never drop) any legacy DP800_Mxx databases as manual cleanup candidates.
Write-Host 'Checking for legacy per-module databases (reported as manual cleanup candidates only; never dropped automatically)...'
& $runner -Server $Server -User $User -Database master -InputFile (Join-Path $PSScriptRoot 'report-legacy-databases.sql')

Write-Host 'AdventureGearAI core bootstrap complete.'
