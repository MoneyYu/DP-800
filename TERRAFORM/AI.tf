locals {
  ai_location            = lower(local.effective_ai_location)
  ai_resource_group_name = "${local.group_name}-AI"
  ai_sql_server_name     = substr("${local.compact_name_prefix}aisql", 0, 63)
  ai_openai_account_name = substr("${local.resource_name_prefix}-ai-openai", 0, 64)
  ai_sample_sql_path     = abspath("${path.module}/sample-data/ecommerce-ai.sql")
  ai_data_plane_script   = abspath("${path.module}/scripts/Deploy-AiDataPlane.ps1")
  ai_validated_japan_east_models = (
    var.ai_embedding_model_name == "text-embedding-3-small" &&
    var.ai_embedding_model_version == "1" &&
    contains(["Standard", "GlobalStandard", "DataZoneStandard"], var.ai_embedding_model_sku) &&
    var.ai_chat_model_name == "gpt-5.4-mini" &&
    var.ai_chat_model_version == "2026-03-17" &&
    var.ai_chat_model_sku == "GlobalStandard"
  )
}

resource "azurerm_resource_group" "core_sql_ai" {
  count = var.enable_core_sql_ai ? 1 : 0

  name     = local.ai_resource_group_name
  location = local.location
  tags     = local.default_tags
}

resource "azurerm_mssql_server" "core_sql_ai" {
  count = var.enable_core_sql_ai ? 1 : 0

  name                          = local.ai_sql_server_name
  resource_group_name           = azurerm_resource_group.core_sql_ai[0].name
  location                      = azurerm_resource_group.core_sql_ai[0].location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  azuread_administrator {
    login_username              = var.ai_entra_admin_login
    object_id                   = local.effective_admin_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_mssql_firewall_rule" "core_sql_ai_deployer" {
  count = var.enable_core_sql_ai ? 1 : 0

  name             = "deployer-client"
  server_id        = azurerm_mssql_server.core_sql_ai[0].id
  start_ip_address = local.effective_allowed_client_ip
  end_ip_address   = local.effective_allowed_client_ip
}

resource "azurerm_mssql_database" "core_sql_ai" {
  count = var.enable_core_sql_ai ? 1 : 0

  name                        = var.ai_sql_database_name
  server_id                   = azurerm_mssql_server.core_sql_ai[0].id
  sku_name                    = var.ai_sql_database_sku
  max_size_gb                 = 32
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
  storage_account_type        = "Local"
  zone_redundant              = false

  short_term_retention_policy {
    retention_days = 7
  }

  tags = local.default_tags
}

resource "azurerm_cognitive_account" "core_sql_ai" {
  count = var.enable_core_sql_ai ? 1 : 0

  name                          = local.ai_openai_account_name
  resource_group_name           = azurerm_resource_group.core_sql_ai[0].name
  location                      = local.ai_location
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = local.ai_openai_account_name
  local_auth_enabled            = false
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    precondition {
      condition     = local.ai_location != "japaneast" || local.ai_validated_japan_east_models
      error_message = "Japan East was validated on 2026-08-03 only for text-embedding-3-small version 1 and gpt-5.4-mini version 2026-03-17 with the declared SKUs. Set ai_location to a region verified for any different model tuple."
    }
  }

  tags = local.default_tags
}

resource "azurerm_cognitive_deployment" "core_sql_ai_embedding" {
  count = var.enable_core_sql_ai ? 1 : 0

  name                   = var.ai_embedding_deployment_name
  cognitive_account_id   = azurerm_cognitive_account.core_sql_ai[0].id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = "OpenAI"
    name    = var.ai_embedding_model_name
    version = var.ai_embedding_model_version
  }

  sku {
    name     = var.ai_embedding_model_sku
    capacity = var.ai_embedding_model_capacity
  }
}

resource "azurerm_cognitive_deployment" "core_sql_ai_chat" {
  count = var.enable_core_sql_ai ? 1 : 0

  name                   = var.ai_chat_deployment_name
  cognitive_account_id   = azurerm_cognitive_account.core_sql_ai[0].id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = "OpenAI"
    name    = var.ai_chat_model_name
    version = var.ai_chat_model_version
  }

  sku {
    name     = var.ai_chat_model_sku
    capacity = var.ai_chat_model_capacity
  }

  depends_on = [
    azurerm_cognitive_deployment.core_sql_ai_embedding,
  ]
}

resource "azurerm_role_assignment" "core_sql_ai_server_openai_user" {
  count = var.enable_core_sql_ai ? 1 : 0

  scope                            = azurerm_cognitive_account.core_sql_ai[0].id
  role_definition_name             = "Cognitive Services OpenAI User"
  principal_id                     = azurerm_mssql_server.core_sql_ai[0].identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "core_sql_ai_deployer_openai_user" {
  count = var.enable_core_sql_ai ? 1 : 0

  scope                = azurerm_cognitive_account.core_sql_ai[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = local.effective_deployer_object_id
}

resource "terraform_data" "core_sql_ai_data_plane" {
  count = var.enable_core_sql_ai && var.enable_data_plane ? 1 : 0

  triggers_replace = [
    azurerm_mssql_database.core_sql_ai[0].id,
    azurerm_cognitive_deployment.core_sql_ai_embedding[0].id,
    azurerm_cognitive_deployment.core_sql_ai_chat[0].id,
    filesha256(local.ai_data_plane_script),
    filesha256(local.ai_sample_sql_path),
  ]

  provisioner "local-exec" {
    command     = "pwsh -NoLogo -NoProfile -NonInteractive -File \"${local.ai_data_plane_script}\""
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-Command"]

    environment = {
      DP800_CHAT_DEPLOYMENT                  = var.ai_chat_deployment_name
      DP800_EMBEDDING_DEPLOYMENT             = var.ai_embedding_deployment_name
      DP800_EMBEDDING_MODEL                  = var.ai_embedding_model_name
      DP800_OPENAI_ENDPOINT                  = azurerm_cognitive_account.core_sql_ai[0].endpoint
      DP800_OPENAI_RESOURCE_ID               = azurerm_cognitive_account.core_sql_ai[0].id
      DP800_SAMPLE_SQL_PATH                  = local.ai_sample_sql_path
      DP800_SQL_DATABASE_NAME                = azurerm_mssql_database.core_sql_ai[0].name
      DP800_SQL_ADMIN_OBJECT_ID              = local.effective_admin_object_id
      DP800_SQL_SERVER_FQDN                  = azurerm_mssql_server.core_sql_ai[0].fully_qualified_domain_name
      DP800_SQL_SERVER_IDENTITY_PRINCIPAL_ID = azurerm_mssql_server.core_sql_ai[0].identity[0].principal_id
      DP800_SQL_SERVER_RESOURCE_ID           = azurerm_mssql_server.core_sql_ai[0].id
    }
  }

  depends_on = [
    azurerm_mssql_firewall_rule.core_sql_ai_deployer,
    azurerm_role_assignment.core_sql_ai_server_openai_user,
    azurerm_role_assignment.core_sql_ai_deployer_openai_user,
  ]
}
