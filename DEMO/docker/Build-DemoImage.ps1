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
$probeOwnerLabel = 'dp800.probe-owner'
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
    foreach ($environmentVariable in 'DP800_SQL_PASSWORD', 'SQLCMDPASSWORD') {
        $password = [Environment]::GetEnvironmentVariable($environmentVariable, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($password)) {
            return $password
        }
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

function Test-ProbeSqlReady {
    param(
        [Parameter(Mandatory)]
        [string]$ContainerName
    )

    & docker exec --env SQLCMDPASSWORD $ContainerName `
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -Q 'SELECT 1;' 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Wait-ForProbeSqlReady {
    param(
        [Parameter(Mandatory)]
        [string]$ContainerName
    )

    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    do {
        if (Test-ProbeSqlReady -ContainerName $ContainerName) {
            return
        }

        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "SQL Server in $ContainerName did not become ready within three minutes."
}

function Invoke-ProbeSqlQuery {
    param(
        [Parameter(Mandatory)]
        [string]$ContainerName,

        [Parameter(Mandatory)]
        [string]$Query
    )

    $output = & docker exec --env SQLCMDPASSWORD $ContainerName `
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -W -h -1 -s '|' -Q $Query 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "SQL query failed in $ContainerName."
    }

    return ($output -join [Environment]::NewLine).Trim()
}

function Get-OwnedProbeContainerId {
    param(
        [Parameter(Mandatory)]
        [string]$ContainerName,

        [Parameter(Mandatory)]
        [string]$OwnerLabel,

        [Parameter(Mandatory)]
        [string]$OwnerToken
    )

    $format = '{{.ID}}|{{.Names}}|{{.Label "' + $OwnerLabel + '"}}'
    $probeContainers = @(& docker ps -a --filter "name=^/$ContainerName$" --format $format)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect Docker containers while cleaning up the temporary probe.'
    }

    $expectedProbe = '^(?<id>[0-9a-f]{12,64})\|' +
        [regex]::Escape($ContainerName) + '\|' +
        [regex]::Escape($OwnerToken) + '$'
    foreach ($probeContainer in $probeContainers) {
        $match = [regex]::Match($probeContainer, $expectedProbe)
        if ($match.Success) {
            return $match.Groups['id'].Value
        }
    }

    return $null
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

$hadMssqlSaPassword = Test-Path Env:MSSQL_SA_PASSWORD
$originalMssqlSaPassword = $env:MSSQL_SA_PASSWORD
$hadSqlcmdPassword = Test-Path Env:SQLCMDPASSWORD
$originalSqlcmdPassword = $env:SQLCMDPASSWORD
$probeOwnerToken = [guid]::NewGuid().ToString('N')
$ownsProbeAttempt = $false
$cleanupError = $null
try {
    $saPassword = Get-SaPassword
    $env:MSSQL_SA_PASSWORD = $saPassword
    $env:SQLCMDPASSWORD = $saPassword
    $saPassword = $null

    $port = if ($PSBoundParameters.ContainsKey('ProbePort')) { $ProbePort } else { Get-AvailableLoopbackPort }
    $portMapping = '127.0.0.1:{0}:1433' -f $port

    $ownsProbeAttempt = $true
    & docker run --detach --name $probeName --publish $portMapping `
        --label "$probeOwnerLabel=$probeOwnerToken" `
        --env 'ACCEPT_EULA=Y' `
        --env 'MSSQL_PID=Developer' `
        --env 'MSSQL_SA_PASSWORD' `
        $imageTag | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to start $probeName on localhost:$port."
    }

    Write-Host "Temporary probe $probeName is running at 127.0.0.1,$port."
    Wait-ForProbeSqlReady -ContainerName $probeName

    $featureValues = Invoke-ProbeSqlQuery -ContainerName $probeName -Query @'
SET NOCOUNT ON;
SELECT CONCAT(
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)), '|',
    CAST(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') AS int), '|',
    CAST(SERVERPROPERTY('IsPolyBaseInstalled') AS int));
'@
    if ($featureValues -notmatch '^(?<version>[^|]+)\|(?<fullText>[01])\|(?<polyBase>[01])$') {
        throw "Unexpected SQL feature query output from $probeName."
    }
    if ($Matches.fullText -ne '1' -or $Matches.polyBase -ne '1') {
        throw "SQL feature validation failed: IsFullTextInstalled=$($Matches.fullText); IsPolyBaseInstalled=$($Matches.polyBase)."
    }
    Write-Host "SQL Server ready: ProductVersion=$($Matches.version); IsFullTextInstalled=$($Matches.fullText); IsPolyBaseInstalled=$($Matches.polyBase)."

    $packageFormat = '${binary:Package}\t${db:Status-Status}\n'
    $packageValues = & docker exec $probeName dpkg-query -W "-f=$packageFormat" `
        mssql-server-fts mssql-server-polybase 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Package validation failed in $probeName."
    }
    $packageValues = ($packageValues -join [Environment]::NewLine).Trim()
    foreach ($packageName in 'mssql-server-fts', 'mssql-server-polybase') {
        if ($packageValues -notmatch "(?m)^$([regex]::Escape($packageName))\s+installed\r?$") {
            throw "Package validation failed: $packageName is not installed."
        }
    }
    Write-Host "Validated installed packages: mssql-server-fts, mssql-server-polybase."
}
finally {
    if ($ownsProbeAttempt) {
        try {
            $ownedProbeId = Get-OwnedProbeContainerId -ContainerName $probeName `
                -OwnerLabel $probeOwnerLabel -OwnerToken $probeOwnerToken
            if ($null -ne $ownedProbeId) {
                & docker rm -f $ownedProbeId | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Removed temporary probe $probeName."
                }
                else {
                    $cleanupError = "Unable to remove temporary probe $probeName."
                }
            }
        }
        catch {
            $cleanupError = $_.Exception.Message
        }
    }

    if ($hadMssqlSaPassword) {
        $env:MSSQL_SA_PASSWORD = $originalMssqlSaPassword
    }
    else {
        Remove-Item Env:MSSQL_SA_PASSWORD -ErrorAction SilentlyContinue
    }
    if ($hadSqlcmdPassword) {
        $env:SQLCMDPASSWORD = $originalSqlcmdPassword
    }
    else {
        Remove-Item Env:SQLCMDPASSWORD -ErrorAction SilentlyContinue
    }

    $saPassword = $null
    if ($null -ne $cleanupError) {
        throw $cleanupError
    }
}
