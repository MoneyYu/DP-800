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
function Test-RecordedMasterKeyCleanupGuard {
    param([AllowEmptyString()][string]$Text)

    # A test-created master key belongs to this test only while its current
    # GUID still exactly matches the GUID recorded at creation time.
    return $Text -match '(?is)\$currentMasterKeyIdentity\s*=\s*Get-Scalar.*?key_guid.*?if\s*\(\s*\[string\]::IsNullOrWhiteSpace\(\$currentMasterKeyIdentity\)\s*\).*?Add-Failure\s+.*?(?:absent|missing).*?elseif\s*\(\s*\$currentMasterKeyIdentity\s*-cne\s*\$testMasterKeyIdentity\s*\).*?Add-Failure\s+.*?(?:changed|differ).*?else\s*\{.*?DROP MASTER KEY;'
}
function Normalize-DockerfileSource {
    param([AllowEmptyString()][string]$Text)

    # This test deliberately recognizes only the repository's canonical recipe.
    # Strip Dockerfile comment lines, then flatten only explicit continuations.
    $normalizedLineEndings = $Text -replace "\r\n?", "`n"
    $withoutComments = $normalizedLineEndings -replace '(?m)^[ \t]*#.*(?:\n|$)', ''
    return $withoutComments -replace '[ \t]*\\\n[ \t]*', ' '
}
function Test-CanonicalSql2025DockerRecipe {
    param([AllowEmptyString()][string]$DockerfileText)

    $source = Normalize-DockerfileSource -Text $DockerfileText
    $expectedInstructions = @(
        [pscustomobject]@{ Keyword = 'FROM'; Arguments = 'mcr.microsoft.com/mssql/server:2025-latest' }
        [pscustomobject]@{ Keyword = 'USER'; Arguments = 'root' }
        [pscustomobject]@{ Keyword = 'RUN'; Arguments = 'wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*' }
        [pscustomobject]@{ Keyword = 'USER'; Arguments = 'mssql' }
        [pscustomobject]@{ Keyword = 'CMD'; Arguments = '["/opt/mssql/bin/sqlservr"]' }
    )
    $actualInstructions = [System.Collections.Generic.List[object]]::new()

    foreach ($line in ($source -split "`n")) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) { continue }

        $match = [regex]::Match($trimmedLine, '^(?<keyword>[A-Za-z]+)(?:[ \t]+(?<arguments>.*))?$')
        if (-not $match.Success) { return $false }

        $actualInstructions.Add([pscustomobject]@{
                Keyword = $match.Groups['keyword'].Value.ToUpperInvariant()
                Arguments = $match.Groups['arguments'].Value.Trim()
            })
    }

    if ($actualInstructions.Count -ne $expectedInstructions.Count) { return $false }

    for ($index = 0; $index -lt $expectedInstructions.Count; $index++) {
        if ($actualInstructions[$index].Keyword -ne $expectedInstructions[$index].Keyword -or
            $actualInstructions[$index].Arguments -cne $expectedInstructions[$index].Arguments) {
            return $false
        }
    }

    return $true
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
$m03M05Runtime = Get-RequiredText 'DEMO\tests\Test-M03M05FeatureCoverageRuntime.ps1'
$m06 = Get-RequiredText 'DEMO\M06\common\01-workload.sql'
$m06Local = @(
    Get-RequiredText 'DEMO\M06\local\01-plans-query-store-dmvs.sql'
    Get-RequiredText 'DEMO\M06\local\07-isolation-rcsi-probe.sql'
    Get-RequiredText 'DEMO\M06\local\08-query-store-plan-forcing.sql'
) -join "`n"
$m06Reset = Get-RequiredText 'DEMO\M06\reset\reset.sql'
$m08 = Get-RequiredText 'DEMO\M08\common\01-product-api.sql'
$m08Config = Get-RequiredText 'DEMO\M08\common\dab-config.json'
$m08Reset = Get-RequiredText 'DEMO\M08\reset\reset.sql'
$m09 = Get-RequiredText 'DEMO\M09\common\01-review-data.sql'
$m09Local = Get-RequiredText 'DEMO\M09\local\01-feature-detection.sql'
$m09Reset = Get-RequiredText 'DEMO\M09\reset\reset.sql'
$m10 = Get-RequiredText 'DEMO\M10\common\01-search-data.sql'
$m10Local = Get-RequiredText 'DEMO\M10\local\01-search.sql'
$m11 = Get-RequiredText 'DEMO\M11\common\01-local-rag.sql'
$m11Local = Get-RequiredText 'DEMO\M11\local\01-build-prompt.sql'
$m11Azure = Get-RequiredText 'DEMO\M11\azure\01-rag-procedure.sql'

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
    @{ Text = $m09; Pattern = '(?is)compatibility_level.{0,300}IF\s+@compatibilityLevel\s*<\s*170'; Message = 'M09 must truthfully skip AI_GENERATE_CHUNKS below compatibility level 170.' },
    @{ Text = $m09; Pattern = '(?i)CREATE\s+TABLE\s+ai\.EmbeddingChunks'; Message = 'M09 must persist generated chunks in ai.EmbeddingChunks.' },
    @{ Text = $m09; Pattern = '(?i)\b(?:ProductID|SourceProductID)\b'; Message = 'M09 chunk rows must retain canonical product provenance.' },
    @{ Text = $m09; Pattern = '(?i)\b(?:ReviewID|SourceReviewID)\b'; Message = 'M09 chunk rows must retain canonical review provenance.' },
    @{ Text = $m09; Pattern = '(?is)\bChunkOrder\b.*\bChunkOffset\b.*\bChunkLength\b.*\bChunkSetID\b'; Message = 'M09 chunks must persist order, offset, length, and chunk-set identifiers.' },
    @{ Text = $m09; Pattern = '(?i)CROSS\s+APPLY\s+AI_GENERATE_CHUNKS\s*\(\s*SOURCE\s*='; Message = 'M09 must CROSS APPLY AI_GENERATE_CHUNKS with a source expression.' },
    @{ Text = $m09; Pattern = '(?i)ENABLE_CHUNK_SET_ID\s*=\s*1'; Message = 'M09 must enable AI_GENERATE_CHUNKS chunk-set IDs.' },
    @{ Text = $m09Reset; Pattern = '(?i)DROP\s+TABLE\s+IF\s+EXISTS\s+ai\.EmbeddingChunks'; Message = 'M09 reset must remove ai.EmbeddingChunks.' },
    @{ Text = "$m10`n$m10Local"; Pattern = '(?i)FREETEXT\s*\('; Message = 'M10 must demonstrate FREETEXT.' },
    @{ Text = $m10Local; Pattern = '(?is)IF\s+@FullTextReady\s*=\s*1.{0,3000}FREETEXT\s*\('; Message = 'M10 must execute FREETEXT only after full-text readiness is confirmed.' },
    @{ Text = "$m11`n$m11Azure"; Pattern = '(?i)FOR\s+JSON\s+PATH\s*,\s*WITHOUT_ARRAY_WRAPPER'; Message = 'M11 must produce a real single-object grounding context.' },
    @{ Text = "$m11`n$m11Azure"; Pattern = '(?i)JSON_QUERY\s*\(\s*CONVERT\s*\(\s*nvarchar\s*\(\s*max\s*\)\s*,\s*(?:p\.)?ProductMetadata\s*\)\s*\)'; Message = 'M11 must preserve native json ProductMetadata as nested JSON.' },
    @{ Text = "$m11`n$m11Azure"; Pattern = '(?i)catalog\.Products'; Message = 'M11 must retain canonical catalog product grounding.' }
)) {
    Assert-Present -Text $requirement.Text -Pattern $requirement.Pattern -Message $requirement.Message
}

# TDE cleanup must never drop a master key whose GUID changed after this test
# created its temporary key. The fixtures protect the guard itself as well as
# the runtime test's use of it.
$guardedMasterKeyCleanupFixture = @'
$currentMasterKeyIdentity = Get-Scalar -Database 'master' -Query @"
SELECT CONVERT(nvarchar(36), key_guid) FROM sys.symmetric_keys;
"@
if ([string]::IsNullOrWhiteSpace($currentMasterKeyIdentity)) {
    Add-Failure 'M05 TDE test-owned master database master key is absent; cleanup will not drop an unknown master key.'
}
elseif ($currentMasterKeyIdentity -cne $testMasterKeyIdentity) {
    Add-Failure 'M05 TDE test-owned master database master key changed; cleanup will not drop a different master key.'
}
else {
    Invoke-Query -Database 'master' -Query 'DROP MASTER KEY;' | Out-Null
}
'@
$unsafeMasterKeyCleanupFixture = @'
if ($createdTestMasterKey) {
    Invoke-Query -Database 'master' -Query 'DROP MASTER KEY;' | Out-Null
}
'@
if (-not (Test-RecordedMasterKeyCleanupGuard -Text $guardedMasterKeyCleanupFixture)) {
    Add-Failure 'TDE master key cleanup guard self-fixture must be accepted.'
}
if (Test-RecordedMasterKeyCleanupGuard -Text $unsafeMasterKeyCleanupFixture) {
    Add-Failure 'TDE master key cleanup guard unsafe self-fixture must be rejected.'
}
if (-not (Test-RecordedMasterKeyCleanupGuard -Text $m03M05Runtime)) {
    Add-Failure 'M03/M05 runtime TDE cleanup must query the current master key GUID and drop only its recorded test-owned key.'
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

# Docker is a required canonical recipe. A future runtime test will build this
# image and query its engine/packages; this static test recognizes no alternate
# Dockerfile or shell syntax.
$dockerFiles = @(
    'DEMO\docker\Build-DemoImage.ps1',
    'DEMO\docker\README.md',
    'DEMO\docker\README.zh-TW.md'
)
foreach ($relative in $dockerFiles) { $null = Get-RequiredText $relative }
$dockerfilePath = Join-Path $repoRoot 'DEMO\docker\Dockerfile'
$dockerfile = $null
if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
    Add-Failure 'Docker canonical recipe asset is missing: DEMO/docker/Dockerfile.'
}
else {
    $dockerfile = Get-Content -LiteralPath $dockerfilePath -Raw
}

$canonicalDockerRecipe = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
'@
$continuedCanonicalDockerRecipe = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO \
    /etc/apt/sources.list.d/mssql-server-2025.list \
    https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    mssql-server-fts mssql-server-polybase \
    && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
'@
$crlfCanonicalDockerRecipe = $canonicalDockerRecipe -replace "`n", "`r`n"
$dockerFixtures = @{
    CurlRecipe = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list -o /etc/apt/sources.list.d/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
'@
    UrlOption = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list /etc/apt/sources.list.d/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
'@
    FakeHeaderUrl = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget --header="X-Repository: https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list" -qO /etc/apt/sources.list.d/mssql-server-2025.list https://untrusted.example/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
'@
    CommentUrl = @'
# RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN curl -fsSL https://untrusted.example/mssql-server-2025.list -o /etc/apt/sources.list.d/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    UntrustedUrl = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN curl -fsSL https://untrusted.example/mssql-server-2025.list -o /etc/apt/sources.list.d/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    VersionPinnedPackages = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts=17.0.0 mssql-server-polybase=17.0.0
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    MissingPackage = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    ReversedPackages = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-polybase mssql-server-fts
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    TrailingRootUser = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN rm -rf /var/lib/apt/lists/*
USER mssql
USER root
'@
    CurlBeforeRootUser = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
USER root
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    InstallBeforeCurl = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    PrependedFromStage = @'
FROM ubuntu:24.04
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN rm -rf /var/lib/apt/lists/*
USER mssql
'@
    LaterFromStage = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list
RUN apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase
RUN rm -rf /var/lib/apt/lists/*
USER mssql
FROM ubuntu:24.04
'@
    ArbitraryRootRun = @'
FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN curl -fsSL https://untrusted.example/install.sh | sh
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
'@
}
foreach ($recipe in $canonicalDockerRecipe, $continuedCanonicalDockerRecipe, $crlfCanonicalDockerRecipe) {
    if (-not (Test-CanonicalSql2025DockerRecipe -DockerfileText $recipe)) {
        Add-Failure 'Canonical Docker recipe self-fixture must be accepted.'
    }
}
foreach ($name in $dockerFixtures.Keys) {
    if (Test-CanonicalSql2025DockerRecipe -DockerfileText $dockerFixtures[$name]) {
        Add-Failure "Canonical Docker recipe self-fixture '$name' must be rejected."
    }
}
if ($null -ne $dockerfile -and -not (Test-CanonicalSql2025DockerRecipe -DockerfileText $dockerfile)) {
    Add-Failure 'DEMO/docker/Dockerfile must use the canonical SQL Server 2025 Docker recipe: exact base image, root-to-mssql user transition, official wget list download, unversioned ordered feature packages, and apt-list cleanup.'
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS (all SQL Server 2025 feature contracts are represented)' -ForegroundColor Green
exit 0
