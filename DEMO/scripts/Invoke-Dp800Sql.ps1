[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputFile,

    [string]$Database = 'AdventureGearAI',
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',

    # Trusted-bootstrap escape hatch. When set, the read-only AdventureGearAI
    # database guard (Assert-DemoDatabase.sql) is NOT executed before the input.
    # Only the core bootstrap initialization path (which creates the marker the
    # guard checks) should set this. The guard is otherwise run automatically for
    # every non-master target; it is never inferred from the input file name.
    [switch]$SkipDatabaseGuard
)

$ErrorActionPreference = 'Stop'

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    throw 'sqlcmd was not found. Install Microsoft sqlcmd and ensure it is on PATH.'
}

$databaseGuard = Join-Path $PSScriptRoot 'Assert-DemoDatabase.sql'

$originalSqlCmdPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$temporaryPassword = $null

try {
    if ($env:DP800_SQL_PASSWORD) {
        $temporaryPassword = $env:DP800_SQL_PASSWORD
    }
    elseif ($env:SQLCMDPASSWORD) {
        $temporaryPassword = $env:SQLCMDPASSWORD
    }
    else {
        $securePassword = Read-Host 'SQL password' -AsSecureString
        $credential = [pscredential]::new($User, $securePassword)
        $temporaryPassword = $credential.GetNetworkCredential().Password
    }

    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $temporaryPassword, 'Process')
    $resolvedInput = (Resolve-Path -LiteralPath $InputFile).Path

    # Run the read-only database guard before any non-master input, unless a
    # trusted bootstrap caller explicitly opted out. This is an explicit switch,
    # not a filename heuristic, so it cannot be spoofed by naming a script.
    if ($Database -ne 'master' -and -not $SkipDatabaseGuard) {
        if (-not (Test-Path -LiteralPath $databaseGuard -PathType Leaf)) {
            throw "Database guard script is missing: $databaseGuard"
        }
        & $sqlcmd.Source -S $Server -U $User -d $Database -i $databaseGuard -b -r 1 -C
        if ($LASTEXITCODE -ne 0) {
            throw "Database guard failed for target '$Database'; refusing to run $resolvedInput."
        }
    }

    & $sqlcmd.Source -S $Server -U $User -d $Database -i $resolvedInput -b -r 1 -C
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed with exit code $LASTEXITCODE while running $resolvedInput."
    }
}
finally {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlCmdPassword, 'Process')
    $temporaryPassword = $null
}
