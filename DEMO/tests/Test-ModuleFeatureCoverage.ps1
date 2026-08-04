[CmdletBinding()]
param()

# Static, deterministic contract for the SQL Server 2025 feature expansion.
# It intentionally reads only the named, existing repository assets and
# accumulates every missing requirement so the implementation work is actionable.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure { param([string]$Message) $script:failures.Add($Message) }
function Get-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing required source asset: $Path"
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw
}
function Assert-Present {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($null -ne $Text -and $Text -notmatch $Pattern) { Add-Failure $Message }
}
function Assert-Absent {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($null -ne $Text -and $Text -match $Pattern) { Add-Failure $Message }
}
function Get-RequiredText {
    param([string]$RelativePath)
    return Get-Text -Path (Join-Path $repoRoot $RelativePath)
}
function Remove-DockerfileComments {
    param([AllowEmptyString()][string]$Text)

    # Dockerfile comments occupy a complete physical line. Deliberately leave
    # inline text alone here so URL fragments such as https://example/#anchor
    # remain available to the shell-command parser.
    return (($Text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}
function Remove-ShellComment {
    param([string]$Command)

    $quote = [char]0
    $escaped = $false
    for ($index = 0; $index -lt $Command.Length; $index++) {
        $character = $Command[$index]
        if ($quote -ne [char]0) {
            if ($escaped) {
                $escaped = $false
                continue
            }
            if ($character -eq '\') {
                $escaped = $true
                continue
            }
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }

        if ($character -eq '"' -or $character -eq "'") {
            $quote = $character
            continue
        }
        if ($character -eq '#' -and (
                $index -eq 0 -or
                [char]::IsWhiteSpace($Command[$index - 1]) -or
                $Command[$index - 1] -in @(';', '&', '|')
            )) {
            return $Command.Substring(0, $index)
        }
    }
    return $Command
}
function Split-ShellCommands {
    param([string]$Command)

    $commands = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $quote = [char]0
    $escaped = $false
    for ($index = 0; $index -lt $Command.Length; $index++) {
        $character = $Command[$index]
        if ($quote -ne [char]0) {
            $null = $current.Append($character)
            if ($escaped) {
                $escaped = $false
                continue
            }
            if ($character -eq '\') {
                $escaped = $true
                continue
            }
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }

        if ($character -eq '"' -or $character -eq "'") {
            $quote = $character
            $null = $current.Append($character)
            continue
        }
        if ($character -eq ';') {
            if ($current.ToString().Trim()) { $commands.Add($current.ToString().Trim()) }
            $null = $current.Clear()
            continue
        }
        if ($character -eq '|' -and $index + 1 -lt $Command.Length -and $Command[$index + 1] -eq '|') {
            if ($current.ToString().Trim()) { $commands.Add($current.ToString().Trim()) }
            $null = $current.Clear()
            $index++
            continue
        }
        if ($character -eq '&' -and $index + 1 -lt $Command.Length -and $Command[$index + 1] -eq '&') {
            if ($current.ToString().Trim()) { $commands.Add($current.ToString().Trim()) }
            $null = $current.Clear()
            $index++
            continue
        }
        $null = $current.Append($character)
    }
    if ($current.ToString().Trim()) { $commands.Add($current.ToString().Trim()) }
    return $commands.ToArray()
}
function ConvertTo-ShellTokens {
    param([string]$Command)

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Command, '"(?:\\.|[^"])*"|''(?:\\.|[^''])*''|[^\s]+')) {
        $token = $match.Value
        if ($token.Length -ge 2 -and (
                ($token.StartsWith('"') -and $token.EndsWith('"')) -or
                ($token.StartsWith("'") -and $token.EndsWith("'"))
            )) {
            $token = $token.Substring(1, $token.Length - 2)
        }
        $tokens.Add($token)
    }
    return $tokens.ToArray()
}
function Get-DockerfileRunCommands {
    param([AllowEmptyString()][string]$Text)

    $commands = [System.Collections.Generic.List[string]]::new()
    $logicalInstruction = [System.Text.StringBuilder]::new()
    foreach ($line in (Remove-DockerfileComments -Text $Text -split "`r?`n")) {
        $trimmedLine = $line.TrimEnd()
        $continues = $trimmedLine.EndsWith('\')
        if ($continues) { $trimmedLine = $trimmedLine.Substring(0, $trimmedLine.Length - 1) }
        $null = $logicalInstruction.Append($trimmedLine).Append(' ')
        if ($continues) { continue }

        $instruction = $logicalInstruction.ToString().Trim()
        $null = $logicalInstruction.Clear()
        if ($instruction -notmatch '(?is)^\s*RUN\s+(?<command>.+)$') { continue }
        foreach ($command in (Split-ShellCommands -Command (Remove-ShellComment -Command $Matches.command))) {
            $commands.Add($command)
        }
    }
    return $commands.ToArray()
}
function Test-AptInstallPackages {
    param(
        [string]$Command,
        [string[]]$Packages
    )

    $tokens = @(ConvertTo-ShellTokens -Command $Command)
    $commandIndex = 0
    while ($commandIndex -lt $tokens.Count -and $tokens[$commandIndex] -match '^[A-Za-z_][A-Za-z0-9_]*=.*$') {
        $commandIndex++
    }
    if ($commandIndex + 1 -ge $tokens.Count -or $tokens[$commandIndex] -notin @('apt-get', 'apt') -or $tokens[$commandIndex + 1] -ne 'install') {
        return $false
    }

    $arguments = @($tokens[($commandIndex + 2)..($tokens.Count - 1)])
    foreach ($package in $Packages) {
        if ($arguments -notcontains $package) { return $false }
    }
    return $true
}
function Test-OfficialSql2025RepositoryConfiguration {
    param([string]$Command)

    $repositoryUrl = 'https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list'
    if ($Command -notmatch [regex]::Escape($repositoryUrl)) { return $false }

    $tokens = @(ConvertTo-ShellTokens -Command $Command)
    $commandIndex = 0
    while ($commandIndex -lt $tokens.Count -and $tokens[$commandIndex] -match '^[A-Za-z_][A-Za-z0-9_]*=.*$') {
        $commandIndex++
    }
    if ($commandIndex -ge $tokens.Count -or $tokens[$commandIndex] -notin @('curl', 'wget')) {
        return $false
    }
    return $Command -match '(?i)(?:\s-o\s+\S*(?:sources\.list\.d|mssql-server-2025\.list)|>\s*\S*(?:sources\.list\.d|mssql-server-2025\.list)|\|\s*tee\s+\S*(?:sources\.list\.d|mssql-server-2025\.list))'
}
function Test-DockerfileFeaturePackageInstall {
    param([AllowEmptyString()][string]$DockerfileText)

    $packages = @('mssql-server-fts', 'mssql-server-polybase')
    $repositoryConfigured = $false
    foreach ($command in (Get-DockerfileRunCommands -Text $DockerfileText)) {
        if (Test-OfficialSql2025RepositoryConfiguration -Command $command) {
            $repositoryConfigured = $true
            continue
        }
        if ($repositoryConfigured -and (Test-AptInstallPackages -Command $command -Packages $packages)) {
            return $true
        }
    }
    return $false
}

Write-Host 'SQL Server 2025 module feature coverage (static)'
Write-Host ''

$bootstrap = Get-RequiredText 'DEMO\bootstrap\01-initialize-adventuregear-demo.sql'
$m01 = Get-RequiredText 'DEMO\M01\common\01-objects.sql'
$m01Local = Get-RequiredText 'DEMO\M01\local\01-inspect.sql'
$m01Reset = Get-RequiredText 'DEMO\M01\reset\reset.sql'
$m03 = Get-RequiredText 'DEMO\M03\local\01-advanced-queries.sql'
$m05 = Get-RequiredText 'DEMO\M05\common\01-security.sql'
$m05Local = Get-RequiredText 'DEMO\M05\local\01-verify-security.sql'
$m05Reset = Get-RequiredText 'DEMO\M05\reset\reset.sql'
$m06 = Get-RequiredText 'DEMO\M06\common\01-workload.sql'
$m06Local = Get-RequiredText 'DEMO\M06\local\01-plans-query-store-dmvs.sql'
$m06Reset = Get-RequiredText 'DEMO\M06\reset\reset.sql'
$m08 = Get-RequiredText 'DEMO\M08\common\01-product-api.sql'
$m08Config = Get-RequiredText 'DEMO\M08\common\dab-config.json'
$m08Reset = Get-RequiredText 'DEMO\M08\reset\reset.sql'
$m09 = Get-RequiredText 'DEMO\M09\common\01-review-data.sql'
$m09Local = Get-RequiredText 'DEMO\M09\local\01-feature-detection.sql'
$m10 = Get-RequiredText 'DEMO\M10\common\01-search-data.sql'
$m10Local = Get-RequiredText 'DEMO\M10\local\01-search.sql'
$m11 = Get-RequiredText 'DEMO\M11\common\01-local-rag.sql'
$m11Local = Get-RequiredText 'DEMO\M11\local\01-build-prompt.sql'

# Bootstrap: native json columns and deterministic, classroom-scale data.
foreach ($column in 'ProductMetadata', 'Preferences', 'ShippingMetadata') {
    Assert-Present -Text $bootstrap -Pattern ("(?i)\b" + $column + "\s+json\b") `
        -Message "Bootstrap must declare $column as the native json data type."
    Assert-Absent -Text $bootstrap -Pattern ("(?i)ISJSON\s*\(\s*" + $column + "\s*\)") `
        -Message "Bootstrap must not retain an ISJSON check for native json column $column."
}

$seedTargets = [ordered]@{
    Category      = 10
    Product       = 150
    Customer      = 120
    Order         = 800
    OrderItem     = 2000
    ProductReview = 500
}
foreach ($target in $seedTargets.GetEnumerator()) {
    $name = [regex]::Escape($target.Key)
    $number = $target.Value
    Assert-Present -Text $bootstrap -Pattern ("(?i)DECLARE\s+@" + $name + "Target\s+\w+\s*=\s*$number\b") `
        -Message "Bootstrap must define the deterministic $($target.Value) $($target.Key) seed cardinality target."
}
Assert-Present -Text $bootstrap -Pattern '(?i)(deterministic|決定性)' `
    -Message 'Bootstrap must state that the large seed is deterministic.'
Assert-Present -Text $bootstrap -Pattern '(?i)(>=|at least|至少)\s*2000|\b2000\b.{0,80}(?:OrderItems|order items)' `
    -Message 'Bootstrap must guarantee at least 2000 order items.'

# M01: SQL Server 2025 core object features plus reset symmetry.
$m01All = "$m01`n$m01Local"
foreach ($requirement in @(
    @{ Pattern = '(?i)CREATE\s+JSON\s+INDEX'; Message = 'M01 must create a JSON index.' },
    @{ Pattern = '(?i)JSON_VALUE\s*\('; Message = 'M01 must demonstrate JSON_VALUE.' },
    @{ Pattern = '(?i)JSON_PATH_EXISTS\s*\('; Message = 'M01 must demonstrate JSON_PATH_EXISTS.' },
    @{ Pattern = '(?i)JSON_CONTAINS\s*\('; Message = 'M01 must demonstrate JSON_CONTAINS.' },
    @{ Pattern = '(?i)\.\s*modify\s*\('; Message = 'M01 must demonstrate native json .modify().' },
    @{ Pattern = '(?i)MEMORY_OPTIMIZED\s*=\s*ON'; Message = 'M01 must create a MEMORY_OPTIMIZED=ON table.' },
    @{ Pattern = '(?i)LEDGER\s*=\s*ON'; Message = 'M01 must create an updatable LEDGER=ON table.' },
    @{ Pattern = '(?i)CREATE\s+SEQUENCE'; Message = 'M01 must create a sequence.' },
    @{ Pattern = '(?i)CREATE\s+EXTERNAL\s+TABLE'; Message = 'M01 must include an external-table demonstration.' },
    @{ Pattern = '(?i)(IsPolyBaseInstalled|external table).{0,300}(TRY|CATCH|IF)|(?:TRY|CATCH|IF).{0,300}(IsPolyBaseInstalled|external table)'; Message = 'M01 must feature-detect external-table/PolyBase availability.' },
    @{ Pattern = '(?i)CONSTRAINT\s+\S+.*\b(CHECK|FOREIGN\s+KEY)\b'; Message = 'M01 must explicitly teach a table constraint.' }
)) {
    Assert-Present -Text $m01All -Pattern $requirement.Pattern -Message $requirement.Message
}
foreach ($pattern in '(?i)DROP\s+(?:JSON\s+)?INDEX', '(?i)DROP\s+TABLE', '(?i)DROP\s+SEQUENCE', '(?i)DROP\s+EXTERNAL\s+TABLE') {
    Assert-Present -Text $m01Reset -Pattern $pattern `
        -Message "M01 reset must contain matching teardown for feature objects ($pattern)."
}
foreach ($feature in 'JSON', 'MEMORY_OPTIMIZED|memory-optimized', 'LEDGER', 'SEQUENCE', 'EXTERNAL') {
    Assert-Present -Text $m01Reset -Pattern ("(?i)" + $feature) `
        -Message "M01 reset must identify its $feature feature teardown."
}

# M03, M05, M06, M08, M09, M10, and M11 feature contracts.
foreach ($requirement in @(
    @{ Text = $m03; Pattern = '(?i)FOR\s+JSON\s+PATH'; Message = 'M03 must demonstrate FOR JSON PATH.' },
    @{ Text = $m03; Pattern = '(?i)JSON_(?:ARRAYAGG|OBJECTAGG)\s*\('; Message = 'M03 must demonstrate JSON_ARRAYAGG or JSON_OBJECTAGG.' },
    @{ Text = $m03; Pattern = '(?i)OPENJSON\s*\(\s*(?:\w+\.)?\w+\.(?:ProductMetadata|Preferences|ShippingMetadata)'; Message = 'M03 must run OPENJSON against a native json column.' },
    @{ Text = $m03; Pattern = '(?i)JSON_CONTAINS\s*\('; Message = 'M03 must demonstrate JSON_CONTAINS.' },
    @{ Text = "$m05`n$m05Local"; Pattern = '(?i)MASKED\s+WITH\s*\(\s*FUNCTION\s*=\s*''default\(\)''\s*\)'; Message = 'M05 must demonstrate default() dynamic data masking.' },
    @{ Text = $m05; Pattern = '(?i)GRANT\s+\w+.+\s+ON\s+(?:OBJECT::)?\S+'; Message = 'M05 must grant an object-level permission.' },
    @{ Text = $m05; Pattern = '(?i)DENY\s+\w+.+\s+ON\s+(?:OBJECT::)?\S+'; Message = 'M05 must deny an object-level permission.' },
    @{ Text = "$m05`n$m05Local`n$m05Reset"; Pattern = '(?i)CREATE\s+DATABASE.{0,120}TDE'; Message = 'M05 must provide an isolated TDE demonstration database.' },
    @{ Text = "$m05`n$m05Local`n$m05Reset"; Pattern = '(?i)DROP\s+DATABASE.{0,120}TDE'; Message = 'M05 isolated TDE demo must include a cleanup path.' },
    @{ Text = "$m06`n$m06Local"; Pattern = '(?i)SET\s+TRANSACTION\s+ISOLATION\s+LEVEL'; Message = 'M06 must demonstrate SET TRANSACTION ISOLATION LEVEL.' },
    @{ Text = "$m06`n$m06Local"; Pattern = '(?i)sp_query_store_force_plan'; Message = 'M06 must demonstrate sp_query_store_force_plan.' },
    @{ Text = "$m06`n$m06Local`n$m06Reset"; Pattern = '(?i)sp_query_store_unforce_plan'; Message = 'M06 must unforce a Query Store plan during cleanup.' },
    @{ Text = "$m08`n$m08Reset"; Pattern = '(?i)sp_cdc_enable'; Message = 'M08 must enable CDC.' },
    @{ Text = "$m08`n$m08Reset"; Pattern = '(?i)sp_cdc_disable'; Message = 'M08 must disable CDC during cleanup.' },
    @{ Text = $m08Config; Pattern = '(?i)"cache"\s*:'; Message = 'M08 DAB configuration must define cache settings.' },
    @{ Text = $m08Config; Pattern = '(?i)"relationships"\s*:'; Message = 'M08 DAB configuration must define entity relationships.' },
    @{ Text = $m08Config; Pattern = '(?i)"type"\s*:\s*"stored-procedure"'; Message = 'M08 DAB configuration must expose a stored-procedure entity.' },
    @{ Text = "$m09`n$m09Local"; Pattern = '(?i)AI_GENERATE_CHUNKS\s*\('; Message = 'M09 must invoke AI_GENERATE_CHUNKS.' },
    @{ Text = $m09; Pattern = '(?i)CREATE\s+TABLE\s+\S*(?:Chunk|chunk)'; Message = 'M09 must persist chunks in a table.' },
    @{ Text = "$m10`n$m10Local"; Pattern = '(?i)FREETEXT\s*\('; Message = 'M10 must demonstrate FREETEXT.' },
    @{ Text = "$m11`n$m11Local"; Pattern = '(?i)WITHOUT_ARRAY_WRAPPER'; Message = 'M11 must demonstrate WITHOUT_ARRAY_WRAPPER.' }
)) {
    Assert-Present -Text $requirement.Text -Pattern $requirement.Pattern -Message $requirement.Message
}

# M01 and DEMO root documentation must distinguish feature support from data volume.
$documentation = @(
    'DEMO\M01\README.md',
    'DEMO\M01\README.zh-TW.md',
    'DEMO\README.md',
    'DEMO\README.zh-TW.md'
)
$documentationTerms = @(
    @{ Pattern = '(?i)\bJSON\b'; Label = 'JSON' },
    @{ Pattern = '(?i)(In-Memory|記憶體)'; Label = 'In-Memory' },
    @{ Pattern = '(?i)(External|外部)'; Label = 'External' },
    @{ Pattern = '(?i)(Ledger|帳本)'; Label = 'Ledger' },
    @{ Pattern = '(?i)(Sequence|序列)'; Label = 'Sequence' },
    @{ Pattern = '(?i)(data[- ]volume|資料量)'; Label = 'data volume' },
    @{ Pattern = '(?i)(feature[- ]detection|功能偵測|功能检测)'; Label = 'feature detection' }
)
foreach ($relative in $documentation) {
    $text = Get-RequiredText $relative
    foreach ($term in $documentationTerms) {
        Assert-Present -Text $text -Pattern $term.Pattern -Message "$relative must document $($term.Label)."
    }
    Assert-Present -Text $text -Pattern '(?is)(?:(?:data[- ]volume|資料量).{0,400}(?:separate|independent|distinct|rather than|different|分別|區別|不同).{0,400}(?:feature[- ]detection|功能偵測)|(?:feature[- ]detection|功能偵測).{0,400}(?:separate|independent|distinct|rather than|different|分別|區別|不同).{0,400}(?:data[- ]volume|資料量))' `
        -Message "$relative must distinguish data volume from feature detection."
}

# Reference ledger: each official M01 source is required in the attendee Links and trainer ledger.
$rootReadme = Get-RequiredText 'README.md'
$linkLedger = Get-RequiredText 'docs\link-ledger.txt'
$m01References = @(
    'https://learn.microsoft.com/en-us/sql/t-sql/data-types/json-data-type?view=sql-server-ver17',
    'https://learn.microsoft.com/en-us/sql/t-sql/statements/create-json-index-transact-sql?view=sql-server-ver17',
    'https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server?view=sql-server-ver17',
    'https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql?view=sql-server-ver17',
    'https://learn.microsoft.com/en-us/sql/relational-databases/in-memory-oltp/introduction-to-memory-optimized-tables?view=sql-server-ver17',
    'https://learn.microsoft.com/en-us/sql/relational-databases/security/ledger/ledger-how-to-updatable-ledger-tables?view=sql-server-ver17',
    'https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-table-transact-sql?view=sql-server-ver17'
)
foreach ($url in $m01References) {
    $escapedUrl = [regex]::Escape($url)
    Assert-Present -Text $rootReadme -Pattern $escapedUrl -Message "README.md Links must include $url."
    Assert-Present -Text $linkLedger -Pattern $escapedUrl -Message "docs/link-ledger.txt must include $url."
}

# Sibling README parity is intentionally narrow: only the newly added feature
# tokens/links are checked, never a full-file comparison.
$moduleParity = @{
    M01 = '(?i)(JSON|MEMORY_OPTIMIZED|LEDGER|SEQUENCE|EXTERNAL)'
    M03 = '(?i)(JSON_ARRAYAGG|JSON_OBJECTAGG|JSON_CONTAINS)'
    M05 = '(?i)(default\(\)|TDE|Transparent Data Encryption)'
    M06 = '(?i)(ISOLATION LEVEL|sp_query_store_force_plan)'
    M08 = '(?i)(CDC|cache|stored-procedure)'
    M09 = '(?i)AI_GENERATE_CHUNKS'
    M10 = '(?i)FREETEXT'
    M11 = '(?i)WITHOUT_ARRAY_WRAPPER'
}
foreach ($module in $moduleParity.Keys) {
    foreach ($name in 'README.md', 'README.zh-TW.md') {
        $relative = "DEMO\$module\$name"
        Assert-Present -Text (Get-RequiredText $relative) -Pattern $moduleParity[$module] `
            -Message "$relative must document its added SQL Server 2025 feature token."
    }
}

# Docker remains a documented, reproducible optional asset rather than a test side effect.
$dockerFiles = @(
    'DEMO\docker\Build-DemoImage.ps1',
    'DEMO\docker\README.md',
    'DEMO\docker\README.zh-TW.md'
)
foreach ($relative in $dockerFiles) { $null = Get-RequiredText $relative }
$dockerfile = Get-RequiredText 'DEMO\docker\Dockerfile'
Assert-Present -Text $dockerfile `
    -Pattern '(?im)^\s*FROM\s+mcr\.microsoft\.com/mssql/server:2025-latest\s*$' `
    -Message 'DEMO/docker/Dockerfile must use exactly mcr.microsoft.com/mssql/server:2025-latest.'

$dockerFixtures = @{
    CommentOnly = @'
# RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list -o /tmp/mssql.list \
#     && apt-get install -y mssql-server-fts mssql-server-polybase
RUN apt-get install -y curl # mssql-server-fts mssql-server-polybase
'@
    UnrelatedInstall = @'
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list -o /etc/apt/sources.list.d/mssql.list \
    && apt-get update \
    && apt-get install -y curl \
    && echo mssql-server-fts mssql-server-polybase
'@
    UnconfiguredRepository = @'
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list > /dev/null \
    && apt-get install -y mssql-server-fts mssql-server-polybase
'@
    Valid = @'
# A URL fragment must remain part of the URL rather than becoming a comment.
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list#fragment -o /etc/apt/sources.list.d/mssql.list \
    && apt-get update \
    && apt install -y mssql-server-fts mssql-server-polybase
'@
}
foreach ($name in 'CommentOnly', 'UnrelatedInstall', 'UnconfiguredRepository') {
    if (Test-DockerfileFeaturePackageInstall -DockerfileText $dockerFixtures[$name]) {
        Add-Failure "Docker parser self-fixture '$name' must reject comments or unrelated package names."
    }
}
if (-not (Test-DockerfileFeaturePackageInstall -DockerfileText $dockerFixtures.Valid)) {
    Add-Failure 'Docker parser self-fixture must accept a continued RUN that configures the official repository and installs both packages.'
}
if ($null -ne $dockerfile -and -not (Test-DockerfileFeaturePackageInstall -DockerfileText $dockerfile)) {
    Add-Failure 'DEMO/docker/Dockerfile must configure the official Ubuntu 24.04 SQL Server 2025 repository before one apt-get install or apt install argument list contains exact mssql-server-fts and mssql-server-polybase tokens.'
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all SQL Server 2025 feature contracts are represented)' -ForegroundColor Green
exit 0
