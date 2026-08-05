# M06 — Optimize database performance

English | [繁體中文](README.zh-TW.md)

Module 6 builds a tunable workload (`ops.PerformanceOrders`) derived from the
canonical **AdventureGearAI** catalog/customer core and demonstrates execution
plans, a covering index, Query Store, and DMV inspection.

## Run it

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 6
```

The runner runs `common/01-workload.sql` then `local/01-plans-query-store-dmvs.sql`
against AdventureGearAI. Both are idempotent; add `-Force` to re-run.

## Interactive concurrency scripts (not run by the runner)

The blocking and deadlock demos require multiple simultaneous sessions and are
**intentionally excluded** from the runner manifest. Run them by hand against
AdventureGearAI:

- Blocking: open three sessions and run `local/02-blocker.sql`,
  `local/03-blocked.sql`, and `local/04-observe-blocking.sql`.
- Deadlock: run `local/05-deadlock-session-a.sql` and
  `local/06-deadlock-session-b.sql` simultaneously.

All scripts target the schema-qualified `ops.PerformanceOrders` object. See
`azure/README.md` for platform differences.
