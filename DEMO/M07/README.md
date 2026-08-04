# M07 — CI/CD with SQL database projects

`common/Dp800.Database` is an SDK-style SQL project (object-per-file, organized
into `catalog`/`ops` schema folders) that builds a dacpac targeting the unified
**AdventureGearAI** database. `DP800.publish.xml` is a passwordless Entra publish
profile scoped to `AdventureGearAI`. Run `local/Build-SqlProject.ps1` to build
(0 warnings/0 errors). `azure/build-deploy.yml` is a sample GitHub Actions
workflow that builds the dacpac and publishes it with a secret connection string
only.

## Execution target

All objects live in `AdventureGearAI` (`catalog.InventoryChangeLog`,
`catalog.usp_LogInventoryChange`, `ops.DeploymentLog`). The unified demo runner
provisions these objects with the hybrid command:

```powershell
pwsh -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 7
```

The runner executes the idempotent `common/01-inventory-deployment-log.sql`
setup script against `AdventureGearAI`; the SQL project build is demonstrated
separately (it produces the dacpac used by the CI/CD workflow), so the manifest
lists the SQL setup script rather than the project build.
