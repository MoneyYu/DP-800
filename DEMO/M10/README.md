# M10 — Full-text, vector, and hybrid search

Run `common/01-search-data.sql`, then `local/01-search.sql` against `DP800_M10`.

Full-text installation and vector syntax are detected independently. The common script expands the five base reviews into 100 fictional search documents so DiskANN meets its minimum vector count. The local script executes what the installed build supports and emits the actual skip reason for the rest. The Azure path uses DiskANN with the current `SELECT TOP (...) WITH APPROXIMATE` query syntax because preview/GA behavior can differ from SQL Server 2025.
