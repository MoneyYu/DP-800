[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$sqlWrapper = Join-Path $repoRoot 'DEMO\scripts\Invoke-Dp800Sql.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure { param([string]$Message) $script:failures.Add($Message) }

Write-Host 'Traditional Chinese SQL encoding runtime regression harness'
Write-Host ''

# This runtime test proves that both sqlcmd and the production wrapper can
# round-trip UTF-8 Chinese text from a no-BOM SQL file.
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $sqlcmd) { Add-Failure 'Required local environment is missing: sqlcmd is not on PATH.' }
if (-not $docker) { Add-Failure 'Required local environment is missing: docker is not on PATH.' }

$password = $null
$temporaryScript = $null
$temporaryBomScript = $null
$originalSqlCmdPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')

try {
    if ($sqlcmd -and $docker) {
        $running = @(& $docker.Source ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container
        if (-not $running) {
            Add-Failure "Required local environment is missing: container '$Container' is not running."
        }
        else {
            # Keep the password only in this process; never echo or persist it.
            $password = (& $docker.Source exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($password)) {
                Add-Failure "Required local environment is missing: MSSQL_SA_PASSWORD is not set in '$Container'."
            }
            else {
                $temporaryScript = Join-Path $repoRoot ('.localization-runtime-{0}.sql' -f [guid]::NewGuid().ToString('N'))
                $sql = @"
-- English localization encoding regression comment
-- 繁體中文註解：確認 UTF-8 SQL 指令碼。
SELECT N'繁中字串測試' AS LocalizationProbe;
"@
                [System.IO.File]::WriteAllText(
                    $temporaryScript,
                    $sql,
                    [System.Text.UTF8Encoding]::new($false))

                [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
                $output = & $sqlcmd.Source -S $Server -U $User -d master -i $temporaryScript -f 65001 -b -r 1 -C -h -1 -W 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Add-Failure "Direct sqlcmd UTF-8 smoke failed with exit $LASTEXITCODE."
                }
                elseif ($output -notmatch [regex]::Escape('繁中字串測試')) {
                    Add-Failure 'Direct sqlcmd UTF-8 smoke did not return the exact Chinese literal.'
                }
                else {
                    Write-Host 'Direct sqlcmd UTF-8 smoke passed.'
                }
                if ($output -match 'ç¹|ä¸') {
                    Add-Failure 'Direct sqlcmd UTF-8 smoke output contains known mojibake.'
                }

                $wrapperOutput = & $sqlWrapper -InputFile $temporaryScript -Database master -Server $Server -User $User 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Add-Failure "Invoke-Dp800Sql UTF-8 no-BOM smoke failed with exit $LASTEXITCODE."
                }
                elseif ($wrapperOutput -notmatch [regex]::Escape('繁中字串測試')) {
                    Add-Failure 'Invoke-Dp800Sql UTF-8 no-BOM smoke did not return the exact Chinese literal.'
                }
                elseif ($wrapperOutput -match 'ç¹|ä¸') {
                    Add-Failure 'Invoke-Dp800Sql UTF-8 no-BOM smoke output contains known mojibake.'
                }
                else {
                    Write-Host 'Invoke-Dp800Sql UTF-8 no-BOM smoke passed.'
                }

                $temporaryBomScript = Join-Path $repoRoot ('.localization-runtime-bom-{0}.sql' -f [guid]::NewGuid().ToString('N'))
                $bomSql = @"
-- English localization encoding regression comment
-- 繁體中文註解：確認 UTF-8 BOM SQL 指令碼。
SELECT N'繁中 BOM 字串測試' AS LocalizationProbe;
"@
                [System.IO.File]::WriteAllText(
                    $temporaryBomScript,
                    $bomSql,
                    [System.Text.UTF8Encoding]::new($true))

                $bomOutput = & $sqlWrapper -InputFile $temporaryBomScript -Database master -Server $Server -User $User 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Add-Failure "Invoke-Dp800Sql UTF-8 BOM smoke failed with exit $LASTEXITCODE."
                }
                elseif ($bomOutput -notmatch [regex]::Escape('繁中 BOM 字串測試')) {
                    Add-Failure 'Invoke-Dp800Sql UTF-8 BOM smoke did not return the exact Chinese literal.'
                }
                elseif ($bomOutput -match 'ç¹|ä¸') {
                    Add-Failure 'Invoke-Dp800Sql UTF-8 BOM smoke output contains known mojibake.'
                }
                else {
                    Write-Host 'Invoke-Dp800Sql UTF-8 BOM smoke passed.'
                }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $sqlWrapper -PathType Leaf)) {
        Add-Failure 'Invoke-Dp800Sql.ps1 is missing.'
    }
    else {
        $wrapperLines = Get-Content -LiteralPath $sqlWrapper
        $sqlcmdInvocationLines = @($wrapperLines | Where-Object { $_ -match '&\s+\$sqlcmd\.Source\b' })
        if ($sqlcmdInvocationLines.Count -eq 0) {
            Add-Failure 'Invoke-Dp800Sql.ps1 does not invoke sqlcmd.'
        }
        elseif (@($sqlcmdInvocationLines | Where-Object { $_ -notmatch '(?<!\S)-f\s+65001(?:\s|$)' }).Count -gt 0) {
            Add-Failure 'Invoke-Dp800Sql.ps1 must pass -f 65001 on every sqlcmd invocation for UTF-8 input/output.'
        }
    }
}
finally {
    if ($temporaryScript -and (Test-Path -LiteralPath $temporaryScript)) {
        Remove-Item -LiteralPath $temporaryScript -Force
    }
    if ($temporaryBomScript -and (Test-Path -LiteralPath $temporaryBomScript)) {
        Remove-Item -LiteralPath $temporaryBomScript -Force
    }
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlCmdPassword, 'Process')
    $password = $null
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (Traditional Chinese SQL encoding checks succeeded)' -ForegroundColor Green
exit 0
