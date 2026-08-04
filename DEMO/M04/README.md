# M04 — AI-assisted SQL workflow

This module does not call a Copilot API and creates no new database objects. It
provides a reviewable instruction example plus a before/after query pair that run
against the canonical **AdventureGearAI** sales/customer core.

## Run it

```powershell
# From the repository root, with $env:DP800_SQL_PASSWORD set:
pwsh -NoProfile -File DEMO/scripts/Invoke-DemoModule.ps1 -Modules 4
```

The runner executes the two read-only local scripts against AdventureGearAI:
- `local/01-review-target.sql` — the intentionally poor input for an
  explain/review/refactor exercise.
- `local/02-reference-improvement.sql` — the reviewed/refactored reference form.

Use `common/copilot-instructions-example.md` as a reviewable instruction example.
Compare a generated answer with the reference improvement; never paste
credentials or production data into a prompt. Add `-Force` to re-run.

Because the scripts are read-only, the module is fully idempotent and leaves the
AdventureGearAI data unchanged. See `azure/README.md`.
