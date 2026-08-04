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

function Test-RetryableSqlError {
    param([Parameter(Mandatory)][string]$Message)

    # Microsoft Entra identity and RBAC propagation.
    if ($Message -match '(?i)\b(401|403)\b|unauthorized|forbidden|token-identified principal|login failed|managed identity|principal') {
        return $true
    }

    # Documented Azure SQL transient fault error numbers, including the serverless
    # auto-pause resume path used by the DP-800 AI database.
    if ($Message -match '(?i)\b(4060|40197|40501|40613|40143|49918|49919|49920|10928|10929|10053|10054|10060)\b') {
        return $true
    }

    if ($Message -match '(?i)is not currently available|transport-level error|timeout expired|semaphore timeout|not enough resources|service is currently busy|please retry|connection was successfully established') {
        return $true
    }

    return $false
}

function Split-SqlBatch {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Script)

    $batches = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $blockCommentDepth = 0
    $inStringLiteral = $false
    $inBracketIdentifier = $false

    foreach ($line in ($Script -split "\r?\n")) {
        $isBatchSeparatorLine = $blockCommentDepth -eq 0 -and
            -not $inStringLiteral -and
            -not $inBracketIdentifier -and
            $line -match '^[ \t]*GO\b'

        if ($isBatchSeparatorLine) {
            # Fail fast instead of mis-splitting on forms this runner cannot honour,
            # such as the repeat-count form GO 5.
            if ($line -notmatch '^[ \t]*GO[ \t]*(?:--.*)?$') {
                throw "Unsupported batch separator '$($line.Trim())'. Only a bare GO, optionally followed by a line comment, is supported."
            }

            [void]$batches.Add($current.ToString())
            [void]$current.Clear()
            continue
        }

        [void]$current.AppendLine($line)

        # Track T-SQL lexical state so a GO inside a comment, string literal or
        # bracketed identifier is never mistaken for a batch separator.
        for ($index = 0; $index -lt $line.Length; $index++) {
            $char = $line[$index]
            $next = if ($index + 1 -lt $line.Length) { $line[$index + 1] } else { [char]0 }

            if ($blockCommentDepth -gt 0) {
                if ($char -eq '*' -and $next -eq '/') { $blockCommentDepth--; $index++ }
                elseif ($char -eq '/' -and $next -eq '*') { $blockCommentDepth++; $index++ }
                continue
            }

            if ($inStringLiteral) {
                if ($char -eq "'") {
                    if ($next -eq "'") { $index++ } else { $inStringLiteral = $false }
                }
                continue
            }

            if ($inBracketIdentifier) {
                if ($char -eq ']') {
                    if ($next -eq ']') { $index++ } else { $inBracketIdentifier = $false }
                }
                continue
            }

            if ($char -eq '-' -and $next -eq '-') { break }
            elseif ($char -eq '/' -and $next -eq '*') { $blockCommentDepth++; $index++ }
            elseif ($char -eq "'") { $inStringLiteral = $true }
            elseif ($char -eq '[') { $inBracketIdentifier = $true }
        }
    }

    if ($current.Length -gt 0) {
        [void]$batches.Add($current.ToString())
    }

    if ($blockCommentDepth -gt 0) {
        throw 'The SQL script ends inside an unterminated block comment.'
    }
    if ($inStringLiteral) {
        throw 'The SQL script ends inside an unterminated string literal.'
    }

    return @($batches.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Expand-SqlScriptVariable {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Script,
        [Parameter(Mandatory)][hashtable]$Variable
    )

    # :setvar declarations in the file only carry placeholders. sqlcmd gives :setvar
    # precedence over supplied variables, so they are removed before substitution.
    $expanded = [regex]::Replace($Script, '(?im)^[ \t]*:setvar\b.*$', '')

    $unsupported = [regex]::Match($expanded, '(?im)^[ \t]*(:[A-Za-z!]+).*$')
    if ($unsupported.Success) {
        throw "Unsupported sqlcmd directive '$($unsupported.Groups[1].Value)' in the SQL script. Only :setvar is handled."
    }

    foreach ($name in $Variable.Keys) {
        $pattern = '\$\(' + [regex]::Escape([string]$name) + '\)'
        $replacement = ([string]$Variable[$name]).Replace('$', '$$')
        $expanded = [regex]::Replace($expanded, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $unresolved = [regex]::Match($expanded, '\$\([^)\r\n]*\)')
    if ($unresolved.Success) {
        throw "Unresolved sqlcmd variable '$($unresolved.Value)' in the SQL script."
    }

    return $expanded
}

function Invoke-SqlScriptFile {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$InputFile,
        [hashtable]$Variable = @{},
        [int]$ConnectionTimeoutSeconds = 30,
        [int]$CommandTimeoutSeconds = 0
    )

    $script = (Get-Content -LiteralPath $InputFile -Raw -Encoding utf8).TrimStart([char]0xFEFF)
    $script = Expand-SqlScriptVariable -Script $script -Variable $Variable
    $batches = Split-SqlBatch -Script $script

    if ($batches.Count -eq 0) {
        throw "The SQL script '$InputFile' contains no executable batches."
    }

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $ServerInstance
    $builder['Initial Catalog'] = $Database
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $false
    $builder['Connect Timeout'] = $ConnectionTimeoutSeconds
    $builder['Application Name'] = 'DP800-Deploy-AiDataPlane'

    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.AccessToken = $AccessToken
    $connection.add_InfoMessage([System.Data.SqlClient.SqlInfoMessageEventHandler] {
            param($eventSender, $eventArgs)
            foreach ($sqlMessage in $eventArgs.Errors) {
                Write-Host "  [sql] $($sqlMessage.Message)"
            }
        })

    try {
        # A single connection is reused so SET NOCOUNT/XACT_ABORT stay in effect for
        # every batch, matching sqlcmd session semantics.
        $connection.Open()

        for ($batchIndex = 0; $batchIndex -lt $batches.Count; $batchIndex++) {
            Write-Host "Executing SQL batch $($batchIndex + 1) of $($batches.Count)."
            $command = $connection.CreateCommand()
            try {
                $command.CommandText = $batches[$batchIndex]
                $command.CommandTimeout = $CommandTimeoutSeconds

                $reader = $command.ExecuteReader()
                try {
                    do {
                        while ($reader.Read()) {
                            $fields = for ($field = 0; $field -lt $reader.FieldCount; $field++) {
                                $value = if ($reader.IsDBNull($field)) { 'NULL' } else { $reader.GetValue($field) }
                                '{0}={1}' -f $reader.GetName($field), $value
                            }
                            Write-Host ('  [row] ' + ($fields -join ' | '))
                        }
                    } while ($reader.NextResult())
                }
                finally {
                    $reader.Dispose()
                }
            }
            catch {
                # Stop at the first SqlException instead of descending to the leaf,
                # otherwise the SQL error number is lost and a transient fault is
                # misclassified as fatal by the retry loop.
                $inner = $_.Exception
                while ($inner -isnot [System.Data.SqlClient.SqlException] -and $null -ne $inner.InnerException) {
                    $inner = $inner.InnerException
                }

                $detail = ''
                if ($inner -is [System.Data.SqlClient.SqlException]) {
                    $detail = " (SQL error $($inner.Number), state $($inner.State), line $($inner.LineNumber))"
                }

                throw [System.Exception]::new(
                    "SQL batch $($batchIndex + 1) of $($batches.Count) failed$detail`: $($inner.Message)",
                    $inner)
            }
            finally {
                $command.Dispose()
            }
        }
    }
    finally {
        $connection.Dispose()
    }
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

$sqlVariables = @{
    DP800_OPENAI_HOST          = $openAiHost
    DP800_EMBEDDING_DEPLOYMENT = $embeddingDeployment
    DP800_EMBEDDING_MODEL      = $embeddingModel
    DP800_CHAT_DEPLOYMENT      = $chatDeployment
}

$maxAttempts = 12
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $token = Get-SqlAccessToken
        Invoke-SqlScriptFile `
            -ServerInstance "tcp:$sqlServerFqdn,1433" `
            -Database $sqlDatabaseName `
            -AccessToken $token `
            -InputFile $sampleSqlPath `
            -Variable $sqlVariables `
            -ConnectionTimeoutSeconds 30 `
            -CommandTimeoutSeconds 0

        Write-Host 'DP-800 SQL-native AI data plane completed successfully.'
        return
    }
    catch {
        $message = $_.Exception.ToString()
        if ($attempt -lt $maxAttempts -and (Test-RetryableSqlError $message)) {
            Write-Warning "A retryable Azure SQL or identity propagation failure occurred (attempt $attempt of $maxAttempts). Retrying in 15 seconds."
            Start-Sleep -Seconds 15
            continue
        }

        throw "DP-800 SQL AI data-plane deployment failed on attempt $attempt. $message"
    }
}

throw "DP-800 SQL AI data-plane deployment did not complete after $maxAttempts attempts."
