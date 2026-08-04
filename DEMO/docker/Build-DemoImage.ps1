[CmdletBinding()]
param(
    [switch]$RunProbe,

    [ValidateRange(1, 65535)]
    [int]$ProbePort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$imageTag = 'dp800-sql2025-demo:latest'
$probeName = 'dp800-sql2025-feature-probe'
$dockerfile = Join-Path $PSScriptRoot 'Dockerfile'

function Get-AvailableLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Get-SaPassword {
    if (-not [string]::IsNullOrWhiteSpace($env:DP800_SQL_PASSWORD)) {
        return $env:DP800_SQL_PASSWORD
    }

    $securePassword = Read-Host -Prompt 'SQL Server sa password for the temporary probe' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required to build the DP-800 SQL Server 2025 demo image.'
}

& docker build --tag $imageTag --file $dockerfile $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Docker build failed for $imageTag."
}

Write-Host "Built $imageTag."
if (-not $RunProbe) {
    return
}

$existingProbe = & docker ps -a --filter "name=^/$probeName$" --format '{{.ID}}'
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect Docker containers before starting the temporary probe.'
}
if (-not [string]::IsNullOrWhiteSpace($existingProbe)) {
    throw "A container named $probeName already exists. Inspect or remove that probe explicitly; mssql2025 is never touched."
}

$saPassword = Get-SaPassword
try {
    $port = if ($PSBoundParameters.ContainsKey('ProbePort')) { $ProbePort } else { Get-AvailableLoopbackPort }
    $portMapping = '{0}:1433' -f $port

    & docker run --detach --name $probeName --publish $portMapping `
        --env 'ACCEPT_EULA=Y' `
        --env 'MSSQL_PID=Developer' `
        --env "MSSQL_SA_PASSWORD=$saPassword" `
        $imageTag | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to start $probeName on localhost:$port."
    }

    Write-Host "Temporary probe $probeName is running at 127.0.0.1,$port."
    Write-Host "Validate it, then remove only this probe with: docker rm -f $probeName"
}
finally {
    $saPassword = $null
}
