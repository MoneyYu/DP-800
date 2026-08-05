# Local DAB

English | [繁體中文](README.zh-TW.md)

1. Install the pinned DAB CLI: `dotnet tool install --global Microsoft.DataApiBuilder --version 2.0.9`.
2. Set `DATABASE_CONNECTION_STRING` in the current process. Build it from the same secure password source used by the SQL wrapper; do not save it in the repository or shell history.
3. Run `dab start --config DEMO/M08/common/dab-config.json`.
4. Test `http://localhost:5000/api/Product` and `http://localhost:5000/graphql`.

Local SQL authentication is only a trainer convenience. The repository does not provide or persist the connection string.

The runtime test, `DEMO/tests/Test-DabIntegrationRuntime.ps1`, installs or uses exactly DAB 2.0.9, runs the normal M08 setup against `mssql2025`, and verifies that the live REST and GraphQL relationship endpoints run with this configuration.
