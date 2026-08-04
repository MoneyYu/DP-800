output "core_sql_ai" {
  description = "Toggle-safe DP-800 SQL AI resource names, endpoints, and model deployment names."
  value = var.enable_core_sql_ai ? {
    resource_group      = azurerm_resource_group.dp300.name
    sql_server_name     = azurerm_mssql_server.core_sql_ai[0].name
    sql_server_endpoint = azurerm_mssql_server.core_sql_ai[0].fully_qualified_domain_name
    sql_database_name   = azurerm_mssql_database.core_sql_ai[0].name
    openai_account_name = azurerm_cognitive_account.core_sql_ai[0].name
    openai_endpoint     = azurerm_cognitive_account.core_sql_ai[0].endpoint
    model_deployments = {
      embedding = azurerm_cognitive_deployment.core_sql_ai_embedding[0].name
      chat      = azurerm_cognitive_deployment.core_sql_ai_chat[0].name
    }
  } : null
}
