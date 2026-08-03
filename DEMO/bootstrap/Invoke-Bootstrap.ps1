[CmdletBinding()]
param(
    [ValidateRange(1, 11)]
    [int[]]$Modules = (1..11),
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa'
)

$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $demoRoot 'scripts\Invoke-Dp800Sql.ps1'

& $runner -Server $Server -User $User -Database master -InputFile (Join-Path $PSScriptRoot '00-create-databases.sql')

foreach ($module in $Modules) {
    $database = 'DP800_M{0:D2}' -f $module
    & $runner -Server $Server -User $User -Database $database -InputFile (Join-Path $PSScriptRoot '01-seed-ecommerce.sql')
}

