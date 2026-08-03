$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '..\common\Dp800.Database\Dp800.Database.sqlproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet SDK is required to build the SQL project.'
}

dotnet build $project
if ($LASTEXITCODE -ne 0) {
    throw 'SQL project build failed.'
}
