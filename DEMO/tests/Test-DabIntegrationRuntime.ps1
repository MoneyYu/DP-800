[CmdletBinding()]
param(
    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',
    [string]$Container = 'mssql2025'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$demoRoot = Join-Path $repoRoot 'DEMO'
$bootstrapScript = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'
$runnerScript = Join-Path $demoRoot 'scripts\Invoke-DemoModule.ps1'
$dabConfig = Join-Path $demoRoot 'M08\common\dab-config.json'
$requiredDabVersion = '2.0.9'
$dabProcess = $null
$createdToolPath = $null
$dabLogPath = $null
$password = $null

function Get-DabCommand {
    $globalDab = Get-Command dab -ErrorAction SilentlyContinue
    if ($globalDab) {
        $version = (& $globalDab.Source --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $version -match "(?<!\d)$([regex]::Escape($requiredDabVersion))(?!\d)") {
            return @{ Path = $globalDab.Source; Version = $version }
        }
    }

    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("DP800-DAB-$requiredDabVersion-$([guid]::NewGuid().ToString('N'))")
    $install = & dotnet tool install --tool-path $toolPath Microsoft.DataApiBuilder --version $requiredDabVersion 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Unable to install Microsoft.DataApiBuilder $requiredDabVersion." }

    $script:createdToolPath = $toolPath
    $tool = Join-Path $toolPath 'dab.exe'
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { $tool = Join-Path $toolPath 'dab' }
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Microsoft.DataApiBuilder $requiredDabVersion did not install a dab executable." }

    $version = (& $tool --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch "(?<!\d)$([regex]::Escape($requiredDabVersion))(?!\d)") {
        throw "Installed DAB CLI is not version $requiredDabVersion."
    }
    return @{ Path = $tool; Version = $version }
}

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Get-RestCollection {
    param([string]$Uri)
    $response = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 5
    $value = $response.PSObject.Properties['value']
    if ($null -eq $value) { throw "DAB REST response at '$Uri' did not contain a value collection." }
    return @($value.Value)
}

function Invoke-DabGraphQl {
    param([string]$Uri, [string]$Query)
    $payload = @{ query = $Query } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 10
}

function Assert-GraphQlSuccess {
    param($Response, [string]$Context)
    if ($null -ne $Response.PSObject.Properties['errors']) {
        $messages = @($Response.errors | ForEach-Object { $_.message }) -join '; '
        throw "DAB GraphQL $Context returned errors: $messages"
    }
    if ($null -eq $Response.PSObject.Properties['data']) { throw "DAB GraphQL $Context returned no data." }
}

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $sqlcmd -or -not $docker) {
    Write-Host 'SKIP: sqlcmd or docker is not available.' -ForegroundColor Yellow
    exit 0
}
if (-not ((& $docker.Source ps --filter "name=$Container" --format '{{.Names}}' 2>$null) -contains $Container)) {
    Write-Host "SKIP: container '$Container' is not running." -ForegroundColor Yellow
    exit 0
}
$password = (& $docker.Source exec $Container printenv MSSQL_SA_PASSWORD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Host "SKIP: MSSQL_SA_PASSWORD is not set in '$Container'." -ForegroundColor Yellow
    exit 0
}

$originalSqlPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
$originalDpPassword = [Environment]::GetEnvironmentVariable('DP800_SQL_PASSWORD', 'Process')
$originalConnectionString = [Environment]::GetEnvironmentVariable('DATABASE_CONNECTION_STRING', 'Process')
$originalAspNetCoreUrls = [Environment]::GetEnvironmentVariable('ASPNETCORE_URLS', 'Process')

try {
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable(
        'DATABASE_CONNECTION_STRING',
        "Server=$Server;Database=AdventureGearAI;User ID=$User;Password=$password;Encrypt=False;TrustServerCertificate=True",
        'Process')

    & pwsh -NoProfile -File $bootstrapScript -Server $Server -User $User | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Core bootstrap failed while preparing the DAB integration test.' }
    & pwsh -NoProfile -File $runnerScript -Server $Server -User $User -Modules 8 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'M08 setup failed while preparing the DAB integration test.' }

    $dab = Get-DabCommand
    $port = Get-FreeLoopbackPort
    $baseUri = "http://127.0.0.1:$port"
    [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS', $baseUri, 'Process')
    $dabLogPath = Join-Path ([System.IO.Path]::GetTempPath()) ("DP800-DAB-log-$([guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dabLogPath -Force | Out-Null
    $dabProcess = Start-Process -FilePath $dab.Path -ArgumentList @('start', '--config', $dabConfig) -WorkingDirectory $repoRoot -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $dabLogPath 'stdout.log') -RedirectStandardError (Join-Path $dabLogPath 'stderr.log')

    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while ([DateTime]::UtcNow -lt $deadline -and -not $dabProcess.HasExited) {
        try {
            $products = Get-RestCollection -Uri "$baseUri/api/Product"
            if ($products.Count -gt 0) { $ready = $true; break }
        }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw 'DAB did not become REST-ready before the timeout.' }

    $productCatalog = Get-RestCollection -Uri "$baseUri/api/ProductCatalog"
    if ($productCatalog.Count -lt 1) { throw 'DAB ProductCatalog REST endpoint returned no read-model rows.' }
    $inventoryAvailability = Get-RestCollection -Uri "$baseUri/api/InventoryAvailability"
    if ($inventoryAvailability.Count -lt 1) { throw 'DAB InventoryAvailability REST endpoint returned no read-model rows.' }

    $introspection = Invoke-DabGraphQl -Uri "$baseUri/graphql" -Query '{ __schema { queryType { fields { name } } } categoryType: __type(name: "Category") { fields { name } } productType: __type(name: "Product") { fields { name } } }'
    Assert-GraphQlSuccess -Response $introspection -Context 'introspection'
    $queryFields = @($introspection.data.__schema.queryType.fields | ForEach-Object { $_.name })
    foreach ($field in 'categories', 'products') {
        if ($queryFields -notcontains $field) { throw "DAB GraphQL introspection did not expose the '$field' query field." }
    }
    $categoryFields = @($introspection.data.categoryType.fields | ForEach-Object { $_.name })
    $productFields = @($introspection.data.productType.fields | ForEach-Object { $_.name })
    if ($categoryFields -notcontains 'products') { throw "DAB GraphQL introspection did not expose Category.products." }
    if ($productFields -notcontains 'category') { throw "DAB GraphQL introspection did not expose Product.category." }

    $categoryResponse = Invoke-DabGraphQl -Uri "$baseUri/graphql" -Query '{ categories(first: 1) { items { products { items { __typename } } } } }'
    Assert-GraphQlSuccess -Response $categoryResponse -Context 'Category.products relationship'
    $categoryProducts = @($categoryResponse.data.categories.items[0].products.items)
    if ($categoryProducts.Count -lt 1) { throw 'DAB GraphQL Category.products relationship returned no products.' }

    $productResponse = Invoke-DabGraphQl -Uri "$baseUri/graphql" -Query '{ products(first: 1) { items { id name category { __typename } } } }'
    Assert-GraphQlSuccess -Response $productResponse -Context 'Product.category relationship'
    if ($null -eq $productResponse.data.products.items[0].category) { throw 'DAB GraphQL Product.category relationship returned null.' }

    Write-Host "PASS (DAB $requiredDabVersion; REST Product, ProductCatalog, InventoryAvailability; GraphQL Category.products and Product.category)" -ForegroundColor Green
}
finally {
    if ($null -ne $dabProcess -and -not $dabProcess.HasExited) {
        Stop-Process -Id $dabProcess.Id -Force -ErrorAction SilentlyContinue
        $dabProcess.WaitForExit()
    }
    if ($createdToolPath -and (Test-Path -LiteralPath $createdToolPath)) {
        Remove-Item -LiteralPath $createdToolPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($dabLogPath -and (Test-Path -LiteralPath $dabLogPath)) {
        Remove-Item -LiteralPath $dabLogPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    [Environment]::SetEnvironmentVariable('DATABASE_CONNECTION_STRING', $originalConnectionString, 'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS', $originalAspNetCoreUrls, 'Process')
    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlPassword, 'Process')
    [Environment]::SetEnvironmentVariable('DP800_SQL_PASSWORD', $originalDpPassword, 'Process')
    $password = $null
}
