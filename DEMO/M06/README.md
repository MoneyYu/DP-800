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

## Interactive concurrency and plan scripts (not run by the runner)

The blocking and deadlock demos require multiple simultaneous sessions and are
**intentionally excluded** from the runner manifest. Run them by hand against
AdventureGearAI:

- Blocking: open three sessions and run `local/02-blocker.sql`,
  `local/03-blocked.sql`, and `local/04-observe-blocking.sql`.
- Deadlock: run `local/05-deadlock-session-a.sql` and
  `local/06-deadlock-session-b.sql` simultaneously.

The isolation/RCSI comparison deliberately uses a marked disposable database,
not AdventureGearAI. Start the probe, then use two sessions for
`09-isolation-writer.sql` and `10-isolation-reader.sql`; run
`11-enable-rcsi.sql` and repeat the two-session comparison, then clean up with
`12-isolation-rcsi-cleanup.sql`:

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M06/local/07-isolation-rcsi-probe.sql
```

The Query Store plan-forcing demonstration is also manual because it captures,
forces, verifies, and unforces a plan while restoring the previous capture mode:

```powershell
pwsh -NoProfile -File DEMO/scripts/Invoke-Dp800Sql.ps1 -Database AdventureGearAI -InputFile DEMO/M06/local/08-query-store-plan-forcing.sql
```

The isolation comparison uses `SET TRANSACTION ISOLATION LEVEL READ COMMITTED`;
the plan demo calls `sp_query_store_force_plan` only after it captures an
eligible plan.

Local SQL Server requires the RCSI setting to be enabled on the disposable
database for the second comparison; Azure SQL Database commonly uses
row-versioning defaults, but the script still reports its actual setting. See
`azure/README.md` for platform differences.
