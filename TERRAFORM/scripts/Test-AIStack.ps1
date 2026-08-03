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
[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Deploy-AiDataPlane.ps1'),
    [ref]$null,
    [ref]$parseErrors
) | Out-Null
Assert-True ($parseErrors.Count -eq 0) "Deploy-AiDataPlane.ps1 has AST parse errors: $($parseErrors -join '; ')"

Write-Host 'AI stack static tests passed.'
