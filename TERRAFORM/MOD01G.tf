resource "azapi_resource" "dbwatcher" {
  count = var.enable_operations ? 1 : 0

  # Database watcher remains a preview service. 2025-01-02 is the latest
  # verified ARM API, and Japan West is a documented supported region.
  type      = "Microsoft.DatabaseWatcher/watchers@2025-01-02"
  name      = "${local.lab01_name}-db-watcher-${local.random_str}"
  location  = "Japan West"
  parent_id = azurerm_resource_group.dp300.id

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags

  body = {
    properties = {

    }
  }
}

resource "azurerm_key_vault" "keyvault" {
  count = var.enable_operations ? 1 : 0

  name                       = "${local.lab01_name}-kv-${var.group_postfix}-${random_string.rid.result}"
  location                   = azurerm_resource_group.dp300.location
  resource_group_name        = azurerm_resource_group.dp300.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true

  network_acls {
    bypass         = "None"
    default_action = "Deny"
    ip_rules       = [local.effective_allowed_client_ip]
  }

  tags = local.default_tags
}

resource "azurerm_role_assignment" "keyvault_deployer" {
  count = var.enable_operations ? 1 : 0

  scope                = azurerm_key_vault.keyvault[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = local.effective_deployer_object_id
}
