# Azure notes

- Azure SQL Database enables TDE by default and manages the service-side
  protection for the AdventureGearAI database; customer-managed keys require Azure
  Key Vault configuration.
- Use Entra users/groups and auditing destinations configured for the Azure
  resource instead of contained SQL users where possible.
- Always Encrypted requires a client with `Column Encryption Setting=Enabled` and
  an approved key store. Do not place key material in this repository.
- DDM is not an encryption boundary, and privileged users can still see unmasked
  values.
