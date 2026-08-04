## MOD-01
resource "azurerm_mssql_server" "lab01" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name                          = "${local.lab01_name}-${var.group_postfix}-azure-sql-${local.random_str}"
  resource_group_name           = azurerm_resource_group.dp300.name
  location                      = azurerm_resource_group.dp300.location
  version                       = "12.0"
  administrator_login           = local.effective_admin_username
  administrator_login_password  = local.effective_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  azuread_administrator {
    login_username              = "DP-800 Entra Admin"
    object_id                   = local.effective_admin_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = false
  }

  tags = local.default_tags
}

resource "azurerm_mssql_server_security_alert_policy" "lab01" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  resource_group_name = azurerm_resource_group.dp300.name
  server_name         = azurerm_mssql_server.lab01[0].name
  state               = "Enabled"

  email_account_admins_enabled = true
}

resource "azurerm_mssql_firewall_rule" "lab0101" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name             = "FirewallRule-Money"
  server_id        = azurerm_mssql_server.lab01[0].id
  start_ip_address = local.effective_allowed_client_ip
  end_ip_address   = local.effective_allowed_client_ip
}

# Azure SQL's 0.0.0.0 rule permits Azure-hosted services from any tenant. It is
# intentionally retained for the Automation/operations classroom demo and can
# be disabled independently when that broad trust boundary is not acceptable.
resource "azurerm_mssql_firewall_rule" "lab0102" {
  count = var.enable_azure_sql_gallery && var.enable_azure_services_firewall_demo ? 1 : 0

  name             = "FirewallRule-Azure"
  server_id        = azurerm_mssql_server.lab01[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_server_extended_auditing_policy" "lab01" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  server_id                               = azurerm_mssql_server.lab01[0].id
  blob_storage_endpoint                   = azurerm_storage_account.lab01[0].primary_blob_endpoint
  storage_account_access_key              = var.enable_legacy_key_auth_demo ? azurerm_storage_account.lab01[0].primary_access_key : null
  storage_account_access_key_is_secondary = false
  storage_account_subscription_id         = data.azurerm_client_config.current.subscription_id
  retention_in_days                       = 7
  log_monitoring_enabled                  = false

  depends_on = [azurerm_role_assignment.lab01_sql_auditing]
}

resource "azurerm_storage_account" "lab01" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  name                     = "${local.lab01_name}stor${var.group_postfix}${local.random_str}"
  resource_group_name      = azurerm_resource_group.dp300.name
  location                 = azurerm_resource_group.dp300.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.enable_legacy_key_auth_demo

  # Explicitly keep blob/container and Azure Files share soft delete disabled so Terraform detects drift.
  blob_properties {}
  share_properties {}

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_role_assignment" "lab01_sql_auditing" {
  count = var.enable_azure_sql_gallery ? 1 : 0

  scope                = azurerm_storage_account.lab01[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_mssql_server.lab01[0].identity[0].principal_id
}
