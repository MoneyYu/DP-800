# M02 — Implement programmability objects

English | [繁體中文](README.zh-TW.md)

Module 2 provisions programmability objects in the **sales** domain schema of the
unified **AdventureGearAI** database. They operate on the canonical
`sales.Orders` / `sales.OrderItems` / `customer.Customers` / `catalog.Products`
core.

## Run it

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 2
```

The runner ensures the core exists (and M01 as a prerequisite where requested),
then runs `common/01-programmability.sql` followed by `local/01-exercise.sql`.
Add `-Force` to re-run a Completed module.

## What it demonstrates

- A reporting view (`sales.vw_CustomerOrderSummary`).
- A scalar function (`sales.fn_OrderTotal`) and an inline TVF
  (`sales.fn_CustomerOrders`).
- A transactional stored procedure (`sales.usp_AddOrderItem`) with `TRY...CATCH`.
- An `AFTER UPDATE` audit trigger (`sales.trg_OrderStatusAudit`) writing to
  `sales.OrderStatusAudit`.

The local exercise wraps its mutations in a transaction that is rolled back, so
the canonical sales data is left unchanged and the module is idempotent. These
objects work on SQL Server 2025 and Azure SQL; see `azure/README.md`.
