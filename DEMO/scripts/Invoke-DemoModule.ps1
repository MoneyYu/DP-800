[CmdletBinding()]
param(
    # Validated integer module numbers. Each element must be 1..11. The default
    # runs every module in ascending dependency order.
    [ValidateRange(1, 11)]
    [int[]]$Modules = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),

    # Re-run modules whose recorded state is already Completed.
    [switch]$Force,

    [string]$Server = '127.0.0.1,1433',
    [string]$User = 'sa',

    # The unified demo provisions exactly one database, literally AdventureGearAI.
    [ValidateSet('AdventureGearAI')]
    [string]$Database = 'AdventureGearAI',

    # Setup ownership manifest. Defaults to the manifest shipped beside this
    # script; tests can supply an alternate manifest that points at safe scripts.
    [string]$ManifestPath,

    # Trusted callers (e.g. Invoke-Bootstrap after it has just initialized the
    # core) can skip the redundant core-bootstrap ensure step.
    [switch]$SkipCoreBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Dependency graph (module -> module prerequisites). "core" (the AdventureGearAI
# bootstrap) is an implicit prerequisite of every module and is ensured
# separately, so it is not listed here.
#   M01            depends on core only
#   M02..M08, M09  depend on core + M01
#   M10            depends on core + M01 + M09
#   M11            depends on core + M01 + M09 + M10
# ---------------------------------------------------------------------------
function Get-DemoModuleDependencyGraph {
    return @{
        1  = @()
        2  = @(1)
        3  = @(1)
        4  = @(1)
        5  = @(1)
        6  = @(1)
        7  = @(1)
        8  = @(1)
        9  = @(1)
        10 = @(1, 9)
        11 = @(1, 9, 10)
    }
}

# Resolve the transitive closure of the requested modules and return them in a
# deterministic topological order: every prerequisite precedes its dependents,
# with ascending module number as the tiebreak so ascending dependency order and
# the requested order are honored wherever the graph allows.
function Resolve-DemoModuleExecutionPlan {
    param(
        [Parameter(Mandatory)][int[]]$Requested,
        [System.Collections.IDictionary]$Graph = (Get-DemoModuleDependencyGraph)
    )

    foreach ($module in $Requested) {
        if (-not $Graph.Contains($module)) {
            throw "Unknown module M$('{0:d2}' -f $module): no dependency-graph entry exists."
        }
    }

    # Transitive closure of requested modules plus all prerequisites.
    $needed = [System.Collections.Generic.HashSet[int]]::new()
    $stack = [System.Collections.Generic.Stack[int]]::new()
    foreach ($module in $Requested) { $stack.Push($module) }
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if (-not $needed.Add($current)) { continue }
        foreach ($dependency in $Graph[$current]) { $stack.Push($dependency) }
    }

    # Kahn topological sort with ascending module number as the stable tiebreak.
    $inDegree = @{}
    foreach ($module in $needed) {
        $inDegree[$module] = @($Graph[$module] | Where-Object { $needed.Contains($_) }).Count
    }

    $ordered = [System.Collections.Generic.List[int]]::new()
    while ($ordered.Count -lt $needed.Count) {
        $ready = @($inDegree.Keys | Where-Object { $inDegree[$_] -eq 0 } | Sort-Object)
        if ($ready.Count -eq 0) {
            throw 'Dependency graph contains a cycle; cannot resolve a module execution order.'
        }
        $next = $ready[0]
        $ordered.Add($next)
        $inDegree.Remove($next)
        foreach ($module in @($inDegree.Keys)) {
            if ($Graph[$module] -contains $next) { $inDegree[$module] = $inDegree[$module] - 1 }
        }
    }

    return $ordered.ToArray()
}

# Load and validate the setup ownership manifest into a module-keyed map.
function Read-DemoModuleManifest {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Module setup manifest not found: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Module setup manifest at '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $raw.modules) {
        throw "Module setup manifest at '$Path' is missing a 'modules' array."
    }

    $manifestDir = Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path
    $map = @{}
    foreach ($entry in $raw.modules) {
        $moduleNumber = [int]$entry.module
        $scopes = [ordered]@{}
        foreach ($scope in 'common', 'local', 'azure') {
            $scriptList = @()
            if ($entry.setup -and ($entry.setup.PSObject.Properties.Name -contains $scope)) {
                $scriptList = @($entry.setup.$scope)
            }
            $scopes[$scope] = @($scriptList)
        }
        $map[$moduleNumber] = [pscustomobject]@{
            Module      = $moduleNumber
            Ready       = [bool]$entry.ready
            Scripts     = $scopes
            ManifestDir = $manifestDir
        }
    }

    return $map
}

# Return the ordered, resolved setup script paths for a module and scope.
# Throws a clear error when the module manifest entry is absent, not ready
# (legacy/unmigrated), or references a script that does not exist. Azure scripts
# are never included in the 'local' scope.
function Get-DemoModuleSetupScripts {
    param(
        [Parameter(Mandatory)][hashtable]$Manifest,
        [Parameter(Mandatory)][int]$Module,
        [ValidateSet('local')][string]$Scope = 'local'
    )

    $moduleName = 'M{0:d2}' -f $Module

    if (-not $Manifest.ContainsKey($Module)) {
        throw "$moduleName has no setup manifest entry; refusing to run it against AdventureGearAI. Populate DEMO/scripts/module-manifest.json when the module is migrated."
    }

    $entry = $Manifest[$Module]
    if (-not $entry.Ready) {
        throw "$moduleName setup manifest is not populated/migrated yet (ready=false); refusing to run legacy module scripts against AdventureGearAI. This is expected until the module is migrated in a later task."
    }

    # Local scope executes common + local setup only, never azure.
    $selectedScopes = @('common', 'local')
    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($scopeName in $selectedScopes) {
        foreach ($relative in @($entry.Scripts[$scopeName])) {
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $candidate = Join-Path $entry.ManifestDir $relative
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "$moduleName setup script listed in the manifest does not exist (incompatible manifest): $relative"
            }
            $resolved.Add((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    if ($resolved.Count -eq 0) {
        throw "$moduleName is marked ready but its manifest lists no common/local setup scripts; refusing to mark it Completed without any work."
    }

    return $resolved.ToArray()
}

# ---------------------------------------------------------------------------
# Secure state access helpers. Module numbers are validated ints (safe to embed).
# Free-text (error details) is never embedded raw: it is single-line-normalized,
# single-quote escaped, truncated, and executed with sqlcmd variable substitution
# disabled (-x) so $(...) sequences cannot be interpreted.
# ---------------------------------------------------------------------------
function Get-SqlcmdPath {
    $sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if (-not $sqlcmd) {
        throw 'sqlcmd was not found. Install Microsoft sqlcmd and ensure it is on PATH.'
    }
    return $sqlcmd.Source
}

function ConvertTo-SafeSqlLiteral {
    param([string]$Value, [int]$MaxLength = 3900)
    if ($null -eq $Value) { return '' }
    $single = ($Value -replace '\s+', ' ').Trim()
    if ($single.Length -gt $MaxLength) { $single = $single.Substring(0, $MaxLength) }
    return ($single -replace "'", "''")
}

function Get-DemoModuleStateMap {
    param(
        [Parameter(Mandatory)][string]$SqlcmdPath,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][int[]]$ModuleNumbers
    )

    $inList = ($ModuleNumbers | Sort-Object -Unique) -join ','
    $query = "SET NOCOUNT ON; SELECT CONCAT(ModuleNumber, '|', Status) FROM ops.DemoModuleState WHERE ModuleNumber IN ($inList) ORDER BY ModuleNumber;"
    $result = & $SqlcmdPath -S $Server -U $User -d $Database -Q $query -h -1 -W -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read ops.DemoModuleState: $($result -join ' ')"
    }

    $map = @{}
    foreach ($line in $result) {
        $text = "$line".Trim()
        if ($text -notmatch '^\d+\|') { continue }
        $parts = $text.Split('|', 2)
        $map[[int]$parts[0]] = $parts[1].Trim()
    }
    return $map
}

function Set-DemoModuleState {
    param(
        [Parameter(Mandatory)][string]$SqlcmdPath,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][int]$Module,
        [Parameter(Mandatory)][ValidateSet('Running', 'Completed', 'Failed')][string]$Status,
        [string]$ErrorText
    )

    $query = Get-DemoModuleStateUpdateSql -Module $Module -Status $Status -ErrorText $ErrorText
    # -I sets QUOTED_IDENTIFIER ON (required to modify a table with a persisted
    # computed column); -x disables sqlcmd variable substitution so $(...) in the
    # error text is inert.
    $result = & $SqlcmdPath -S $Server -U $User -d $Database -Q $query -b -C -I -x 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update ops.DemoModuleState for module $Module -> $Status : $($result -join ' ')"
    }
}

# Build the parameter-safe UPDATE for a module state transition. Module numbers
# are validated ints; free-text error details are normalized/escaped so no
# unvalidated arbitrary input is interpolated into the statement.
function Get-DemoModuleStateUpdateSql {
    param(
        [Parameter(Mandatory)][int]$Module,
        [Parameter(Mandatory)][ValidateSet('Running', 'Completed', 'Failed')][string]$Status,
        [string]$ErrorText
    )

    if ($Module -lt 1 -or $Module -gt 11) {
        throw "Invalid module number '$Module' for a state update."
    }

    switch ($Status) {
        'Running' {
            $set = "Status=N'Running', StartedAtUtc=SYSUTCDATETIME(), CompletedAtUtc=NULL, LastError=NULL, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME()"
        }
        'Completed' {
            $set = "Status=N'Completed', CompletedAtUtc=SYSUTCDATETIME(), LastError=NULL, ErrorNumber=NULL, ErrorLine=NULL, UpdatedAtUtc=SYSUTCDATETIME()"
        }
        'Failed' {
            $safe = ConvertTo-SafeSqlLiteral -Value $ErrorText
            $set = "Status=N'Failed', CompletedAtUtc=SYSUTCDATETIME(), LastError=N'$safe', UpdatedAtUtc=SYSUTCDATETIME()"
        }
    }

    return "SET NOCOUNT ON; UPDATE ops.DemoModuleState SET $set WHERE ModuleNumber=$Module;"
}

# Pure decision helper: a module should run unless it is already Completed and
# -Force was not supplied.
function Test-DemoModuleShouldRun {
    param(
        [Parameter(Mandatory)][string]$CurrentStatus,
        [switch]$Force
    )

    if ($CurrentStatus -eq 'Completed' -and -not $Force) { return $false }
    return $true
}

# ---------------------------------------------------------------------------
# Runner entry point.
# ---------------------------------------------------------------------------
function Invoke-DemoModuleRunner {
    param(
        [int[]]$Modules = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
        [switch]$Force,
        [string]$Server = '127.0.0.1,1433',
        [string]$User = 'sa',
        [string]$Database = 'AdventureGearAI',
        [string]$ManifestPath,
        [switch]$SkipCoreBootstrap
    )

    if ($Database -ne 'AdventureGearAI') {
        throw "The unified demo runner targets only the AdventureGearAI database; '$Database' is not supported."
    }
    if ($null -eq $Modules -or $Modules.Count -eq 0) {
        throw 'No modules were requested. Provide -Modules with values in 1..11.'
    }
    foreach ($module in $Modules) {
        if ($module -lt 1 -or $module -gt 11) {
            throw "Invalid module number '$module'. Module numbers must be integers in 1..11."
        }
    }

    $scriptRoot = $PSScriptRoot
    if (-not $ManifestPath) {
        $ManifestPath = Join-Path $scriptRoot 'module-manifest.json'
    }
    $sqlRunner = Join-Path $scriptRoot 'Invoke-Dp800Sql.ps1'
    $demoRoot = Split-Path -Parent $scriptRoot
    $coreBootstrap = Join-Path $demoRoot 'bootstrap\Invoke-Bootstrap.ps1'

    $manifest = Read-DemoModuleManifest -Path $ManifestPath
    $plan = Resolve-DemoModuleExecutionPlan -Requested $Modules
    $sqlcmdPath = Get-SqlcmdPath

    Write-Host "Requested modules: $((@($Modules) | ForEach-Object { 'M{0:d2}' -f $_ }) -join ', ')"
    Write-Host "Resolved execution plan (dependency order): $((@($plan) | ForEach-Object { 'M{0:d2}' -f $_ }) -join ', ')"

    # ---------------------------------------------------------------------------
    # Password resolution: prefer DP800_SQL_PASSWORD, then existing SQLCMDPASSWORD,
    # else prompt once via a secure read. The plaintext is stored only in
    # SQLCMDPASSWORD (process scope) for the duration of this runner; it is
    # restored to its original value in the finally block.
    # ---------------------------------------------------------------------------
    $originalSqlCmdPassword = [Environment]::GetEnvironmentVariable('SQLCMDPASSWORD', 'Process')
    $temporaryPassword = $null

    if ($env:DP800_SQL_PASSWORD) {
        $temporaryPassword = $env:DP800_SQL_PASSWORD
    }
    elseif ($env:SQLCMDPASSWORD) {
        $temporaryPassword = $env:SQLCMDPASSWORD
    }
    else {
        $securePassword = Read-Host 'SQL password' -AsSecureString
        $credential = [pscredential]::new($User, $securePassword)
        $temporaryPassword = $credential.GetNetworkCredential().Password
    }

    [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $temporaryPassword, 'Process')

    try {

    # Ensure the AdventureGearAI core (database, schemas, marker, state rows).
    # The runner invokes the core-only bootstrap (no -Modules), so it never
    # recurses back into this runner. The bootstrap subprocess inherits
    # SQLCMDPASSWORD; DP800_SQL_PASSWORD is also inherited so the bootstrap
    # can resolve the password via its own Invoke-Dp800Sql calls without
    # prompting again.
    if (-not $SkipCoreBootstrap) {
        Write-Host 'Ensuring AdventureGearAI core bootstrap exists...'
        & pwsh -NoProfile -File $coreBootstrap -Server $Server -User $User -Database $Database
        if ($LASTEXITCODE -ne 0) {
            throw "Core bootstrap failed (exit code $LASTEXITCODE); cannot run modules."
        }
    }

    $state = Get-DemoModuleStateMap -SqlcmdPath $sqlcmdPath -Server $Server -User $User -Database $Database -ModuleNumbers $plan

    foreach ($module in $plan) {
        $moduleName = 'M{0:d2}' -f $module
        $currentStatus = if ($state.ContainsKey($module)) { $state[$module] } else { 'NotStarted' }

        if (-not (Test-DemoModuleShouldRun -CurrentStatus $currentStatus -Force:$Force)) {
            Write-Host "$moduleName is already Completed; skipping (use -Force to re-run)."
            continue
        }

        Write-Host "${moduleName}: marking Running..."
        Set-DemoModuleState -SqlcmdPath $sqlcmdPath -Server $Server -User $User -Database $Database -Module $module -Status 'Running'

        try {
            $setupScripts = Get-DemoModuleSetupScripts -Manifest $manifest -Module $module -Scope 'local'
            foreach ($script in $setupScripts) {
                Write-Host "${moduleName}: running setup script $(Split-Path -Leaf $script)"
                # The subprocess inherits SQLCMDPASSWORD set above, so Invoke-Dp800Sql
                # will resolve it from that env var without prompting.
                & pwsh -NoProfile -File $sqlRunner -Server $Server -User $User -Database $Database -InputFile $script
                if ($LASTEXITCODE -ne 0) {
                    throw "Setup script '$script' failed with exit code $LASTEXITCODE."
                }
            }

            # Succeeded: only after every available setup script finished.
            Set-DemoModuleState -SqlcmdPath $sqlcmdPath -Server $Server -User $User -Database $Database -Module $module -Status 'Completed'
            Write-Host "${moduleName}: Completed."
        }
        catch {
            $details = $_.Exception.Message
            try {
                Set-DemoModuleState -SqlcmdPath $sqlcmdPath -Server $Server -User $User -Database $Database -Module $module -Status 'Failed' -ErrorText $details
            }
            catch {
                Write-Warning "Additionally failed to record the Failed state for $moduleName : $($_.Exception.Message)"
            }
            Write-Host "${moduleName}: Failed - $details" -ForegroundColor Red
            throw
        }
    }

    Write-Host 'Module runner completed successfully.' -ForegroundColor Green

    }
    finally {
        [Environment]::SetEnvironmentVariable('SQLCMDPASSWORD', $originalSqlCmdPassword, 'Process')
        $temporaryPassword = $null
    }
}

# Only run the main body when executed as a script (pwsh -File / &). When the
# file is dot-sourced (for unit testing) the functions are defined but nothing
# runs, so tests can exercise the pure resolution/manifest logic without a DB.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DemoModuleRunner -Modules $Modules -Force:$Force -Server $Server -User $User -Database $Database -ManifestPath $ManifestPath -SkipCoreBootstrap:$SkipCoreBootstrap
}
