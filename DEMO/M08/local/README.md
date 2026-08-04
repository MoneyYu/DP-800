# Local DAB

English | [繁體中文](README.zh-TW.md)

1. Install the DAB CLI: `dotnet tool install --global Microsoft.DataApiBuilder`.
2. Set `DATABASE_CONNECTION_STRING` in the current process. Build it from the same secure password source used by the SQL wrapper; do not save it in the repository or shell history.
3. Run `dab start --config DEMO/M08/common/dab-config.json`.
4. Test `http://localhost:5000/api/Product` and `http://localhost:5000/graphql`.

Local SQL authentication is only a trainer convenience. The repository does not provide or persist the connection string.
