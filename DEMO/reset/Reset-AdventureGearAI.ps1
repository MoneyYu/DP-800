<#
    Reset-AdventureGearAI.ps1

    Full (database-level) reset wrapper for the unified AdventureGearAI demo.

    Hard-scoped by design:
      * It exposes NO arbitrary database parameter. The destructive target is
        never a caller-supplied value.
      * It connects only to the literal master control database and runs the
        literal reset-adventuregear.sql asset (the only DROP DATABASE-bearing
        script in the demo, itself hard-scoped to AdventureGearAI).
      * It then invokes the core bootstrap (core only, without requesting any
        modules) so the flow cannot recurse into the module runner, leaving a
        freshly bootstrapped core AdventureGearAI.

    Secure password handling is delegated to the shared scripts: both
    Invoke-Dp800Sql.ps1 and Invoke-Bootstrap.ps1 resolve the SQL password from
    DP800_SQL_PASSWORD / SQLCMDPASSWORD (or a one-time secure prompt). No password
    is ever accepted, echoed, or embedded here.
#>
[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$demoRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $demoRoot 'scripts\Invoke-Dp800Sql.ps1'
$bootstrap = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'

Write-Host 'Full reset: rolling back sessions and dropping the AdventureGearAI database...'

# 1) Drop AdventureGearAI via the literal, hard-scoped SQL asset (master only).
& $runner -Server $Server -User $User -Database master -InputFile (Join-Path $PSScriptRoot 'reset-adventuregear.sql')
if ($LASTEXITCODE -ne 0) {
    throw "Full reset SQL asset failed with exit code $LASTEXITCODE."
}

# 2) Recreate a freshly bootstrapped core AdventureGearAI. The core bootstrap is
#    invoked WITHOUT requesting any modules, so it provisions only the core and
#    never delegates to the module runner (no recursion).
Write-Host 'Full reset: re-running the core bootstrap to recreate AdventureGearAI...'
& pwsh -NoProfile -File $bootstrap -Server $Server -User $User
if ($LASTEXITCODE -ne 0) {
    throw "Core bootstrap after full reset failed with exit code $LASTEXITCODE."
}

Write-Host 'Full reset complete: AdventureGearAI dropped and freshly bootstrapped.' -ForegroundColor Green
