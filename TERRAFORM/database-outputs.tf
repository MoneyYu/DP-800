output "postgresql_flexible_server" {
  description = "Name and non-secret endpoint of the PostgreSQL Flexible Server."
  value = {
    name          = try(one(azurerm_postgresql_flexible_server.lab01f[*].name), null)
    fqdn          = try(one(azurerm_postgresql_flexible_server.lab01f[*].fqdn), null)
    database_name = try(one(azurerm_postgresql_flexible_server_database.lab01f[*].name), null)
  }
}

output "azure_sql_hyperscale_database" {
  description = "Name of the Azure SQL Hyperscale demonstration database."
  value       = try(one(azurerm_mssql_database.lab01e[*].name), null)
}
