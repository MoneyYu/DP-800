# M05 — Data security and compliance

Run `common/01-security.sql`, then `local/01-verify-security.sql` against `DP800_M05`.

Dynamic Data Masking and Row-Level Security execute locally. TDE is inspected because certificate/key lifecycle differs by platform and should not be automated with a hardcoded master-key password. Always Encrypted encryption is performed by a configured client driver, so the demo creates the target shape and explains the client step rather than pretending server-side T-SQL encrypts the values.

