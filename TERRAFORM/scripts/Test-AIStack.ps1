[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$terraformRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-Text {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $terraformRoot $RelativePath
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing required file: $RelativePath"
    return Get-Content -LiteralPath $path -Raw
}

$aiTerraform = Get-Text 'AI.tf'
$aiVariables = Get-Text 'ai-variables.tf'
$aiOutputs = Get-Text 'ai-outputs.tf'
$deployScript = Get-Text 'scripts\Deploy-AiDataPlane.ps1'
$sampleSql = Get-Text 'sample-data\ecommerce-ai.sql'

Assert-True ($aiTerraform -notmatch 'azurerm_search_service') 'The core SQL AI stack must not create Azure AI Search.'
Assert-True ($aiTerraform -match 'local_auth_enabled\s*=\s*false') 'Azure OpenAI local authentication must be disabled.'
Assert-True ($aiTerraform -match 'custom_subdomain_name\s*=') 'Azure OpenAI requires a custom subdomain for Entra authentication.'
Assert-True ($aiTerraform -match 'minimum_tls_version\s*=\s*"1\.2"') 'Azure SQL must enforce TLS 1.2.'
Assert-True ($aiTerraform -match 'type\s*=\s*"SystemAssigned"') 'Azure SQL must have a system-assigned managed identity.'
Assert-True ($aiTerraform -match 'Cognitive Services OpenAI User') 'Managed identity and deployer OpenAI User role assignments are required.'
Assert-True ($aiVariables -match 'default\s*=\s*"text-embedding-3-small"') 'The validated embedding model default is missing.'
Assert-True ($aiVariables -match 'default\s*=\s*"gpt-5\.4-mini"') 'The validated chat model default is missing.'
Assert-True ($aiVariables -match 'default\s*=\s*"2026-03-17"') 'The validated gpt-5.4-mini version is missing.'
Assert-True (([regex]::Matches($aiTerraform, 'version_upgrade_option\s*=\s*"NoAutoUpgrade"')).Count -eq 2) 'Both model deployments must stay pinned to validated versions.'
Assert-True ($aiOutputs -notmatch '(?i)(password|key|token|secret)') 'AI outputs must not expose secrets.'

foreach ($syntax in @(
        'CREATE EXTERNAL MODEL',
        'AI_GENERATE_EMBEDDINGS',
        'CREATE VECTOR INDEX',
        'VECTOR_SEARCH',
        'CREATE FULLTEXT INDEX',
        'FREETEXTTABLE',
        'sp_invoke_external_rest_endpoint',
        "IDENTITY = 'Managed Identity'"
    )) {
    Assert-True ($sampleSql -match [regex]::Escape($syntax)) "Sample SQL is missing required official syntax: $syntax"
}

Assert-True ($sampleSql -match 'Full-text population timed out') 'Full-text polling must throw on timeout.'
Assert-True ($sampleSql -match 'HTTP status[\s\S]{0,100}@ReturnValue') 'RAG failures must retain HTTP status for 401/403 retry detection.'
Assert-True ($sampleSql -match 'CREATE DATABASE SCOPED CREDENTIAL[\s\S]{0,200}\]\s*WITH\s+IDENTITY') 'Managed identity credential syntax must match the official lab form without a parenthesized WITH clause.'
Assert-True ($deployScript -match '\b401\|403\b') 'The data-plane script must recognize RBAC 401/403 propagation failures.'

$environmentBlock = [regex]::Match(
    $aiTerraform,
    '(?ms)environment\s*=\s*\{(?<body>.*?)^\s*\}'
)
Assert-True $environmentBlock.Success 'Terraform data-plane environment map was not found.'

$terraformEnvironmentNames = [regex]::Matches(
    $environmentBlock.Groups['body'].Value,
    '(?m)^\s*(DP800_[A-Z0-9_]+)\s*='
) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

$scriptEnvironmentNames = [regex]::Matches(
    $deployScript,
    "Get-RequiredEnv\s+'(DP800_[A-Z0-9_]+)'"
) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

Assert-True (
    -not (Compare-Object $terraformEnvironmentNames $scriptEnvironmentNames)
) 'Terraform environment map names do not exactly match Deploy-AiDataPlane.ps1 requirements.'

$parseErrors = $null
$deployScriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Deploy-AiDataPlane.ps1'),
    [ref]$null,
    [ref]$parseErrors
)
Assert-True ($parseErrors.Count -eq 0) "Deploy-AiDataPlane.ps1 has AST parse errors: $($parseErrors -join '; ')"

Assert-True ($deployScript -notmatch 'Invoke-Sqlcmd|Import-Module\s+SqlServer') 'The data-plane script must not depend on the SqlServer module.'

# The script emulates only a restricted subset of sqlcmd. These functional tests
# guard that subset so edits to ecommerce-ai.sql cannot silently break deployment.
$requiredFunctions = 'Split-SqlBatch', 'Expand-SqlScriptVariable', 'Test-RetryableSqlError'
$functionDefinitions = $deployScriptAst.FindAll(
    { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] },
    $false
) | Where-Object { $requiredFunctions -contains $_.Name }

Assert-True (
    $functionDefinitions.Count -eq $requiredFunctions.Count
) 'Deploy-AiDataPlane.ps1 must define Split-SqlBatch, Expand-SqlScriptVariable and Test-RetryableSqlError.'

foreach ($definition in $functionDefinitions) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

$sampleVariables = @{
    DP800_OPENAI_HOST          = 'contoso-test.openai.azure.com'
    DP800_EMBEDDING_DEPLOYMENT = 'text-embedding-3-small'
    DP800_EMBEDDING_MODEL      = 'text-embedding-3-small'
    DP800_CHAT_DEPLOYMENT      = 'gpt-5.4-mini'
}

$expandedSql = Expand-SqlScriptVariable -Script $sampleSql -Variable $sampleVariables
Assert-True ($expandedSql -notmatch '(?im)^[ \t]*:setvar') 'Placeholder :setvar declarations must be stripped before execution.'
Assert-True (-not $expandedSql.Contains('REPLACE_AT_RUNTIME')) 'No placeholder value may survive variable expansion.'
Assert-True (-not [regex]::IsMatch($expandedSql, '\$\([^)\r\n]*\)')) 'No sqlcmd variable may remain unresolved.'
Assert-True ($expandedSql.Contains('contoso-test.openai.azure.com')) 'The Azure OpenAI host must be substituted.'

$sampleBatches = Split-SqlBatch -Script $expandedSql
$sampleGoCount = ([regex]::Matches($sampleSql, '(?im)^[ \t]*GO[ \t\r]*$')).Count
Assert-True ($sampleGoCount -gt 0) 'The sample SQL must use GO batch separators.'
Assert-True (
    $sampleBatches.Count -eq $sampleGoCount
) "Batch splitting produced $($sampleBatches.Count) batches for $sampleGoCount GO separators."
Assert-True (
    -not ($sampleBatches | Where-Object { $_ -match '(?im)^[ \t]*GO[ \t]*$' })
) 'No executable batch may still contain a GO separator.'

Assert-True ((Split-SqlBatch -Script "SELECT 1;`nGO`nSELECT 2;`nGO`n").Count -eq 2) 'A trailing GO must not create an empty batch.'
Assert-True ((Split-SqlBatch -Script "SELECT '`nGO`n' AS x;`nGO`nSELECT 2;").Count -eq 2) 'GO inside a string literal must not split a batch.'
Assert-True ((Split-SqlBatch -Script "/*`nGO`n*/`nSELECT 1;`nGO`nSELECT 2;").Count -eq 2) 'GO inside a block comment must not split a batch.'
Assert-True ((Split-SqlBatch -Script "SELECT 1 AS [a`nGO`nb];`nGO`nSELECT 2;").Count -eq 2) 'GO inside a bracketed identifier must not split a batch.'
Assert-True ((Split-SqlBatch -Script "SELECT N'it''s ok';`nGO`nSELECT 2;").Count -eq 2) 'Escaped quotes must not corrupt lexical state.'
Assert-True ((Split-SqlBatch -Script "SELECT 1;`ngo   -- done`nSELECT 2;").Count -eq 2) 'A lowercase go with a trailing comment must split a batch.'

foreach ($rejected in @(
        @{ Script = "SELECT 1;`nGO 5`nSELECT 2;"; Message = 'GO with a repeat count must be rejected.' },
        @{ Script = "/* never closed`nSELECT 1;"; Message = 'An unterminated block comment must be rejected.' }
    )) {
    $threw = $false
    try { Split-SqlBatch -Script $rejected.Script | Out-Null } catch { $threw = $true }
    Assert-True $threw $rejected.Message
}

$threw = $false
try { Expand-SqlScriptVariable -Script 'SELECT $(MISSING);' -Variable $sampleVariables | Out-Null } catch { $threw = $true }
Assert-True $threw 'An unresolved sqlcmd variable must be rejected.'

$threw = $false
try { Expand-SqlScriptVariable -Script ":connect other`nSELECT 1;" -Variable $sampleVariables | Out-Null } catch { $threw = $true }
Assert-True $threw 'An unsupported sqlcmd directive must be rejected.'

Assert-True (
    (Expand-SqlScriptVariable -Script 'v=$(A)' -Variable @{ A = 'a$1b' }) -eq 'v=a$1b'
) 'A dollar sign in a variable value must not be treated as a regex group reference.'

Assert-True (
    Test-RetryableSqlError 'SQL batch 1 of 20 failed (SQL error 40613, state 1, line 1): Database is not currently available.'
) 'Serverless resume error 40613 must be retried.'
Assert-True (
    Test-RetryableSqlError 'Login failed for user'
) 'Identity propagation failures must be retried.'
Assert-True (
    -not (Test-RetryableSqlError 'SQL batch 20 of 20 failed (SQL error 51120, state 1, line 5): Embedding smoke test failed.')
) 'A deterministic smoke-test failure must not be retried.'

Write-Host 'AI stack static tests passed.'
