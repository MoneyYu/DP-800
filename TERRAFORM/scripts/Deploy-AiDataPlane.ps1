[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Deploy-AiDataPlane.ps1 requires PowerShell 7 or later.'
}

function Get-RequiredEnv {
    param([Parameter(Mandatory)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable '$Name' is missing."
    }

    return $value
}

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & az @Arguments --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments -join ' ')"
    }

    return $output | ConvertFrom-Json
}

function Wait-Until {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutSeconds = 300,
        [int]$IntervalSeconds = 10
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            if (& $Condition) {
                return
            }
        }
        catch {
            Write-Warning "$Description is not ready: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds $IntervalSeconds
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    throw "Timed out after $TimeoutSeconds seconds waiting for $Description."
}

function Get-SqlAccessToken {
    $token = & az account get-access-token `
        --resource 'https://database.windows.net/' `
        --query accessToken `
        --only-show-errors `
        -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Unable to acquire an Azure SQL access token with Azure CLI. Run az login first.'
    }

    return $token.Trim()
}

function Get-TokenObjectId {
    param([Parameter(Mandatory)][string]$Token)

    $parts = $Token.Split('.')
    if ($parts.Count -lt 2) {
        throw 'Azure SQL access token is not a valid JWT.'
    }

    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    $payload += '=' * ((4 - ($payload.Length % 4)) % 4)
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($claims.oid)) {
        throw 'Azure SQL access token does not contain an oid claim.'
    }

    return ([string]$claims.oid).ToLowerInvariant()
}

function Test-RetryablePropagationError {
    param([Parameter(Mandatory)][string]$Message)

    return $Message -match '(?i)\b(401|403)\b|unauthorized|forbidden|token-identified principal|login failed|managed identity|principal'
}

$sqlServerFqdn = Get-RequiredEnv 'DP800_SQL_SERVER_FQDN'
$sqlDatabaseName = Get-RequiredEnv 'DP800_SQL_DATABASE_NAME'
$sqlAdminObjectId = (Get-RequiredEnv 'DP800_SQL_ADMIN_OBJECT_ID').ToLowerInvariant()
$sqlServerResourceId = Get-RequiredEnv 'DP800_SQL_SERVER_RESOURCE_ID'
$sqlServerIdentityPrincipalId = Get-RequiredEnv 'DP800_SQL_SERVER_IDENTITY_PRINCIPAL_ID'
$openAiResourceId = Get-RequiredEnv 'DP800_OPENAI_RESOURCE_ID'
$openAiEndpoint = Get-RequiredEnv 'DP800_OPENAI_ENDPOINT'
$embeddingDeployment = Get-RequiredEnv 'DP800_EMBEDDING_DEPLOYMENT'
$embeddingModel = Get-RequiredEnv 'DP800_EMBEDDING_MODEL'
$chatDeployment = Get-RequiredEnv 'DP800_CHAT_DEPLOYMENT'
$sampleSqlPath = Get-RequiredEnv 'DP800_SAMPLE_SQL_PATH'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install Azure CLI and run az login.'
}

if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    Import-Module SqlServer -ErrorAction SilentlyContinue
}
if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'Invoke-Sqlcmd is required. Install-Module SqlServer -Scope CurrentUser, then rerun Terraform apply.'
}

if (-not (Test-Path -LiteralPath $sampleSqlPath -PathType Leaf)) {
    throw "Sample SQL file was not found: $sampleSqlPath"
}

$identityProbeToken = Get-SqlAccessToken
$cliObjectId = Get-TokenObjectId -Token $identityProbeToken
$identityProbeToken = $null
if ($cliObjectId -ne $sqlAdminObjectId) {
    throw "The active Azure CLI identity object ID does not match the configured Azure SQL administrator object ID '$sqlAdminObjectId'."
}

$openAiHost = ([Uri]$openAiEndpoint).Host

Wait-Until -Description 'Azure SQL managed identity publication' -Condition {
    $resource = Invoke-AzJson @('resource', 'show', '--ids', $sqlServerResourceId)
    return $resource.identity.principalId -eq $sqlServerIdentityPrincipalId
}

Wait-Until -Description 'Cognitive Services OpenAI User RBAC propagation' -Condition {
    $assignments = Invoke-AzJson @(
        'role', 'assignment', 'list',
        '--scope', $openAiResourceId,
        '--assignee-object-id', $sqlServerIdentityPrincipalId
    )
    return @($assignments).Where({ $_.roleDefinitionName -eq 'Cognitive Services OpenAI User' }).Count -gt 0
}

$sqlVariables = @(
    "DP800_OPENAI_HOST=$openAiHost",
    "DP800_EMBEDDING_DEPLOYMENT=$embeddingDeployment",
    "DP800_EMBEDDING_MODEL=$embeddingModel",
    "DP800_CHAT_DEPLOYMENT=$chatDeployment"
)

$maxAttempts = 12
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $token = Get-SqlAccessToken
        Invoke-Sqlcmd `
            -ServerInstance "tcp:$sqlServerFqdn,1433" `
            -Database $sqlDatabaseName `
            -AccessToken $token `
            -InputFile $sampleSqlPath `
            -Variable $sqlVariables `
            -ConnectionTimeout 30 `
            -QueryTimeout 0 `
            -AbortOnError `
            -OutputSqlErrors $true `
            -Verbose

        Write-Host 'DP-800 SQL-native AI data plane completed successfully.'
        return
    }
    catch {
        $message = $_.Exception.ToString()
        if ($attempt -lt $maxAttempts -and (Test-RetryablePropagationError $message)) {
            Write-Warning "RBAC or identity propagation is incomplete (attempt $attempt of $maxAttempts). Retrying in 15 seconds."
            Start-Sleep -Seconds 15
            continue
        }

        throw "DP-800 SQL AI data-plane deployment failed on attempt $attempt. $message"
    }
}

throw "DP-800 SQL AI data-plane deployment did not complete after $maxAttempts attempts."
