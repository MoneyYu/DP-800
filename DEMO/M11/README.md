# M11 — RAG with SQL

Run `common/01-local-rag.sql`, then `local/01-build-prompt.sql` against `DP800_M11`.

The local path demonstrates retrieval, JSON context, and prompt construction. SQL Server 2025 can expose `sp_invoke_external_rest_endpoint`, so the script reports whether the procedure exists; generation is still skipped unless an approved endpoint and database scoped credential are configured. `azure/01-rag-procedure.sql` shows the managed-identity REST pattern with runtime SQLCMD variables.
