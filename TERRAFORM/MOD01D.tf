## MOD-01-D-SQL-DATABASE-ELASTIC-POOL
resource "azurerm_mssql_elasticpool" "lab01d" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name                = "${local.lab01d_name}-elasticpool-${local.random_str}"
  resource_group_name = azurerm_resource_group.dp300.name
  location            = azurerm_resource_group.dp300.location
  server_name         = azurerm_mssql_server.lab01[0].name
  max_size_gb         = 100

  sku {
    name     = "StandardPool"
    tier     = "Standard"
    capacity = 100
  }

  per_database_settings {
    min_capacity = 0
    max_capacity = 100
  }

  tags = local.default_tags
}

resource "azurerm_mssql_database" "lab01d01" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name            = "${local.lab01d_name}-elastic01-db-${local.random_str}"
  server_id       = azurerm_mssql_server.lab01[0].id
  sku_name        = "ElasticPool"
  elastic_pool_id = azurerm_mssql_elasticpool.lab01d[0].id

  tags = local.default_tags
}

resource "azurerm_mssql_database" "lab01d02" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name            = "${local.lab01d_name}-elastic02-db-${local.random_str}"
  server_id       = azurerm_mssql_server.lab01[0].id
  sku_name        = "ElasticPool"
  elastic_pool_id = azurerm_mssql_elasticpool.lab01d[0].id

  tags = local.default_tags
}

resource "azurerm_mssql_database_extended_auditing_policy" "lab01d01" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  database_id                             = azurerm_mssql_database.lab01d01[0].id
  blob_storage_endpoint                   = azurerm_storage_account.lab01[0].primary_blob_endpoint
  storage_account_access_key              = var.enable_legacy_key_auth_demo ? azurerm_storage_account.lab01[0].primary_access_key : null
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
  log_monitoring_enabled                  = false

  depends_on = [azurerm_role_assignment.lab01_sql_auditing]
}

resource "azurerm_mssql_database_extended_auditing_policy" "lab01d02" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  database_id                             = azurerm_mssql_database.lab01d02[0].id
  blob_storage_endpoint                   = azurerm_storage_account.lab01[0].primary_blob_endpoint
  storage_account_access_key              = var.enable_legacy_key_auth_demo ? azurerm_storage_account.lab01[0].primary_access_key : null
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
  log_monitoring_enabled                  = false

  depends_on = [azurerm_role_assignment.lab01_sql_auditing]
}
