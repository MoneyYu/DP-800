# M06 — Optimize database performance

Run `common/01-workload.sql` and `local/01-plans-query-store-dmvs.sql` against `DP800_M06`.

For blocking, open three sessions and follow `local/02-blocker.sql`, `03-blocked.sql`, and `04-observe-blocking.sql`. For a deadlock, run `05-deadlock-session-a.sql` and `06-deadlock-session-b.sql` simultaneously. These concurrency scripts are intentionally interactive and are not suitable for unattended sequential execution.

