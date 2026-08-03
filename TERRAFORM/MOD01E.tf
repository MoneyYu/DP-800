## MOD-01-E-SQL-DATABASE-HYPERSCALE
resource "azurerm_mssql_database" "lab01e" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name         = "${local.lab01e_name}-hyperscale-db-${local.random_str}"
  server_id    = azurerm_mssql_server.lab01[0].id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  sku_name     = "HS_Gen5_2"
  license_type = "BasePrice"
  max_size_gb  = 32
  read_scale   = false

  tags = local.default_tags
}

resource "azurerm_mssql_database_extended_auditing_policy" "lab01e" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  database_id                             = azurerm_mssql_database.lab01e[0].id
  blob_storage_endpoint                   = azurerm_storage_account.lab01[0].primary_blob_endpoint
  storage_account_access_key              = var.enable_legacy_key_auth_demo ? azurerm_storage_account.lab01[0].primary_access_key : null
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
  log_monitoring_enabled                  = false

  depends_on = [azurerm_role_assignment.lab01_sql_auditing]
}
