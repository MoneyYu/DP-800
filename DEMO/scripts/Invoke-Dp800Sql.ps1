[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputFile,

    [string]$Database = 'master',
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa'
)

$ErrorActionPreference = 'Stop'

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    throw 'sqlcmd was not found. Install Microsoft sqlcmd and ensure it is on PATH.'
}

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

    & $sqlcmd.Source -S $Server -U $User -d $Database -i $resolvedInput -b -r 1 -C
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed with exit code $LASTEXITCODE while running $resolvedInput."
    }
}
finally {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlCmdPassword, 'Process')
    $temporaryPassword = $null
}

