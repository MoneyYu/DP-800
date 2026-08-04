# M05 — Data security and compliance

Module 5 demonstrates data-protection features on the canonical **AdventureGearAI**
customer data. It does not replace `customer.Customers`; it provisions a secured
companion projection (`security.SecureCustomers`) that carries the demo-only
sensitive columns Dynamic Data Masking needs, plus a Row-Level Security policy in
the `security` schema.

## Run it

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 5
```

The runner runs `common/01-security.sql` then `local/01-verify-security.sql`
against AdventureGearAI. The demo users are unique to this module and are reset
(dropped/recreated) on every run, so re-running with `-Force` is safe.

## What it demonstrates

- Dynamic Data Masking (`email()`, `partial`, `random`) on the secured projection.
- Row-Level Security via `security.fn_RegionFilter` + `security.CustomerRegionPolicy`.
- TDE inspection (`sys.databases.is_encrypted`).
- The Always Encrypted client-driver boundary (explained, not faked server-side).

TDE certificate/key lifecycle differs by platform and is not automated with a
hardcoded master-key password. DDM is not an encryption boundary; privileged
users still see unmasked values. See `azure/README.md`.
