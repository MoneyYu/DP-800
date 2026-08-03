# M09 — Models and embeddings with SQL

Run `common/01-review-data.sql`, then `local/01-feature-detection.sql` against `DP800_M09`.

The local script records the real engine/version and tests whether the `vector` type can be used. It reports external-model and embedding work as skipped unless the engine and an endpoint configuration support them. `azure/01-external-model.sql` is a managed-identity template; supply SQLCMD variables at execution time.
