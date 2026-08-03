## MOD-01-F-POSTGRESQL-FLEXIBLE
resource "azurerm_postgresql_flexible_server" "lab01f" {
  count = var.enable_postgresql_flexible ? 1 : 0

  name                = "${local.lab01f_name}-${var.group_postfix}-postgres-flex-${local.random_str}"
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name

  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768
  version    = "16"

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  administrator_login    = local.effective_admin_username
  administrator_password = local.effective_admin_password

  public_network_access_enabled = true

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 18
    start_minute = 0
  }

  tags = local.default_tags
}

resource "azurerm_postgresql_flexible_server_database" "lab01f" {
  count = var.enable_postgresql_flexible ? 1 : 0

  name      = "${local.lab01f_name}-postgres-db-${local.random_str}"
  server_id = azurerm_postgresql_flexible_server.lab01f[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "lab01f01" {
  count = var.enable_postgresql_flexible ? 1 : 0

  name             = "AllowedClient"
  server_id        = azurerm_postgresql_flexible_server.lab01f[0].id
  start_ip_address = local.effective_allowed_client_ip
  end_ip_address   = local.effective_allowed_client_ip
}
