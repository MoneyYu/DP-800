# M01 — Design and implement database objects

Run `common/01-objects.sql`, then `local/01-inspect.sql` against `DP800_M01`.

The demo covers constraints and indexes, a system-versioned temporal price table, indexed JSON properties, range partitioning, and SQL graph node/edge tables. Azure SQL supports the core objects, but filegroup and storage decisions differ from boxed SQL Server.

Use `reset/reset.sql` only from `master`; it drops only `DP800_M01`.
