# M03 — Write advanced T-SQL

English | [繁體中文](README.zh-TW.md)

Module 3 demonstrates advanced query techniques against **AdventureGearAI**. A
self-contained org-chart teaching object (`ops.EmployeeHierarchy` plus graph
node/edge tables) supports the recursive-CTE and graph demos, while the
window-function, JSON, and fuzzy-matching queries run over the canonical
`catalog` and `customer` core.

## Run it

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 3
```

The runner ensures the core (and M01 prerequisite where requested), then runs
`common/01-advanced-objects.sql` followed by `local/01-advanced-queries.sql`.
Add `-Force` to re-run a Completed module.

## What it demonstrates

- Recursive CTE org-chart traversal.
- Window functions (`ROW_NUMBER`, partitioned `SUM`) over catalog products.
- `OPENJSON` document shredding.
- `FOR JSON PATH` output plus `JSON_ARRAYAGG` relational-to-JSON aggregation
  and `JSON_CONTAINS` against native JSON.
- `SOUNDEX` / `DIFFERENCE` fuzzy matching.
- SQL graph `MATCH` traversal.
- Runtime detection of SQL Server 2025 `REGEXP_LIKE` over customer emails.
- Structured `TRY...CATCH` error handling with a rolled-back transaction.

Regular-expression support is version-sensitive; the script reports the detected
result rather than assuming parity. See `azure/README.md`.
