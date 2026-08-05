# Azure notes

English | [繁體中文](README.zh-TW.md)

Run the common and query scripts against the AdventureGearAI database on the
target Azure SQL server and record the engine edition/version. Regular-expression
functions such as `REGEXP_LIKE` are version-sensitive, so retain the
feature-detection result rather than assuming parity with a local SQL Server 2025
build. Recursive CTEs, window functions, `OPENJSON`, and SQL graph `MATCH` are
supported on Azure SQL.
