output "root_configuration" {
  description = "Common DP-800 root values for downstream resource groups and modules."
  value = {
    resource_group_name  = try(one(azurerm_resource_group.dp300[*].name), null)
    default_location     = local.location
    ai_location          = local.effective_ai_location
    resource_name_prefix = local.resource_name_prefix
    compact_name_prefix  = local.compact_name_prefix
    feature_toggles      = local.feature_toggles
    default_tags         = local.default_tags
  }
}

output "azure_sql" {
  description = "Names and endpoint of the currently declared Azure SQL resources."
  value = {
    server_name = try(one(azurerm_mssql_server.lab01[*].name), null)
    server_fqdn = try(one(azurerm_mssql_server.lab01[*].fully_qualified_domain_name), null)
    database_names = compact([
      try(one(azurerm_mssql_database.lab01c[*].name), null),
      try(one(azurerm_mssql_database.lab01d01[*].name), null),
      try(one(azurerm_mssql_database.lab01d02[*].name), null),
    ])
  }
}

output "sql_managed_instance" {
  description = "Name and endpoint of the currently declared SQL Managed Instance."
  value = {
    name = try(one(azurerm_mssql_managed_instance.lab01b[*].name), null)
    fqdn = try(one(azurerm_mssql_managed_instance.lab01b[*].fqdn), null)
  }
}

output "sql_virtual_machines" {
  description = "Names and public endpoints of the currently declared SQL Server virtual machines."
  value = {
    sql_2019 = {
      name      = try(one(azurerm_windows_virtual_machine.lab01a[*].name), null)
      public_ip = try(one(azurerm_public_ip.lab01a[*].ip_address), null)
      fqdn      = try(one(azurerm_public_ip.lab01a[*].fqdn), null)
    }
    sql_2022 = {
      name      = try(one(azurerm_windows_virtual_machine.lab01h[*].name), null)
      public_ip = try(one(azurerm_public_ip.lab01h[*].ip_address), null)
      fqdn      = try(one(azurerm_public_ip.lab01h[*].fqdn), null)
    }
  }
}

output "operations_resources" {
  description = "Names and non-secret endpoints of the currently declared operations resources."
  value = {
    database_watcher_name   = try(one(azapi_resource.dbwatcher[*].name), null)
    key_vault_name          = try(one(azurerm_key_vault.keyvault[*].name), null)
    key_vault_uri           = try(one(azurerm_key_vault.keyvault[*].vault_uri), null)
    automation_account_name = try(one(azurerm_automation_account.lab01i[*].name), null)
  }
}
