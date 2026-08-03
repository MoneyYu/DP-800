locals {
  group_name            = "DP800-${var.group_postfix}"
  group_name_lower      = lower(local.group_name)
  resource_name_prefix  = local.group_name_lower
  compact_name_prefix   = replace(local.group_name_lower, "-", "")
  location              = var.location
  effective_ai_location = coalesce(var.ai_location, var.location)
  effective_allowed_client_ip = coalesce(
    var.allowed_client_ip,
    chomp(data.http.myip.response_body),
  )

  # Explicitly supplied deprecated aliases take precedence during migration;
  # their null defaults ensure canonical credentials drive normal runs.
  effective_admin_username = coalesce(var.user_name, var.admin_username)
  effective_admin_password = try(coalesce(var.user_passowrd, var.admin_password), null)
  effective_admin_object_id = coalesce(
    var.admin_object_id,
    data.azurerm_client_config.current.object_id,
  )
  effective_deployer_object_id = coalesce(
    var.deployer_object_id,
    data.azurerm_client_config.current.object_id,
  )

  # Legacy aliases keep unmodified MOD files syntactically valid.
  admin_oid  = local.effective_admin_object_id
  random_str = "tue"

  lab01_name  = "lab01"
  lab01a_name = "lab01a"
  lab01b_name = "lab01b"
  lab01c_name = "lab01c"
  lab01d_name = "lab01d"
  lab01e_name = "lab01e"
  lab01f_name = "lab01f"
  lab01g_name = "lab01g"
  lab01h_name = "lab01h"
  lab02_name  = "lab02"
  lab03_name  = "lab03"
  lab04_name  = "lab04"
  lab05_name  = "lab05"
  lab06_name  = "lab06"
  lab07_name  = "lab07"

  feature_toggles = {
    core_sql_ai          = var.enable_core_sql_ai
    azure_sql_gallery    = var.enable_azure_sql_gallery
    sql_managed_instance = var.enable_sql_managed_instance
    sql_vm_2019          = var.enable_sql_vm_2019
    sql_vm_2022          = var.enable_sql_vm_2022
    postgresql_flexible  = var.enable_postgresql_flexible
    operations           = var.enable_operations
    data_plane           = var.enable_data_plane
  }

  default_tags = {
    environment     = local.group_name
    course          = "DP-800"
    managed_by      = "Terraform"
    workload        = "database-ai"
    SecurityControl = "Ignore"
  }
}
