# T-SQL development instructions

- Prefix every object with its schema.
- Use explicit column lists; never generate `SELECT *`.
- Use ANSI joins and parameterized predicates.
- Stored procedures use `SET NOCOUNT ON`, `SET XACT_ABORT ON`, and `TRY...CATCH` around transactions.
- Explain local SQL Server versus Azure SQL feature differences.
- Never emit passwords, tokens, tenant IDs, object IDs, or credential-bearing connection strings.
- Before suggesting an index, explain the target predicate, expected benefit, and write overhead.
