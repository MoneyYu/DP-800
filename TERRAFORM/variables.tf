variable "subscription_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Azure subscription ID. When null, AzureRM uses ARM_SUBSCRIPTION_ID or the active Azure CLI subscription."

  validation {
    condition     = var.subscription_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be null or a valid UUID."
  }
}

variable "group_postfix" {
  type        = string
  description = "Lowercase suffix used to create the DP800 resource group and globally unique resource names."

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.group_postfix))
    error_message = "group_postfix must contain 1 to 10 lowercase letters or digits."
  }
}

variable "confirm_new_dp800_state" {
  type        = bool
  description = "Explicit confirmation that this configuration uses a new DP-800 state/workspace rather than an existing DP-300 state."

  validation {
    condition     = var.confirm_new_dp800_state
    error_message = "Set confirm_new_dp800_state=true only after selecting a new DP-800 state/workspace. This configuration is not an in-place migration for DP-300 state."
  }
}

variable "confirm_ai_resource_group_consolidation" {
  type        = bool
  default     = false
  description = "Explicit acknowledgement required before any AI-enabled plan/apply because consolidating an existing separate AI resource group can replace resources; this is an acknowledgement, not a feature toggle."
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "Default Azure region for DP-800 resources."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region slug such as japaneast."
  }
}

variable "ai_location" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional narrow override used only by AI/model resources when the required model is unavailable in Japan East."

  validation {
    condition     = var.ai_location == null || can(regex("^[a-z0-9]+$", var.ai_location))
    error_message = "ai_location must be null or an Azure region slug."
  }
}

variable "admin_username" {
  type        = string
  default     = "demouser"
  description = "Administrator username for demo database servers and virtual machines."

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9._-]{0,19}$", var.admin_username))
    error_message = "admin_username must start with a letter and contain at most 20 letters, digits, periods, underscores, or hyphens."
  }
}

variable "admin_password" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "Administrator password required only when a password-based database or VM environment is enabled. Supply it securely at runtime; never commit it to Terraform files or tfvars."

  validation {
    condition = var.admin_password == null ? (
      var.user_passowrd != null || !(
        var.enable_azure_sql_gallery ||
        var.enable_sql_managed_instance ||
        var.enable_sql_vm_2019 ||
        var.enable_sql_vm_2022 ||
        var.enable_postgresql_flexible
      )
      ) : (
      length(var.admin_password) >= 12 &&
      length(var.admin_password) <= 72 &&
      can(regex("[A-Z]", var.admin_password)) &&
      can(regex("[a-z]", var.admin_password)) &&
      can(regex("[0-9]", var.admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.admin_password))
    )
    error_message = "Set admin_password (or deprecated user_passowrd) when a password-based database or VM environment is enabled. The password must be 12 to 72 characters and include uppercase, lowercase, numeric, and special characters."
  }
}

variable "admin_object_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Microsoft Entra administrator object ID. Defaults to the current AzureRM client identity."

  validation {
    condition     = var.admin_object_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.admin_object_id))
    error_message = "admin_object_id must be null or a valid UUID."
  }
}

variable "deployer_object_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Microsoft Entra deployer object ID for RBAC assignments. Defaults to the current AzureRM client identity."

  validation {
    condition     = var.deployer_object_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.deployer_object_id))
    error_message = "deployer_object_id must be null or a valid UUID."
  }
}

variable "allowed_client_ip" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional public IPv4 address allowed through demo firewalls. When null, the HTTPS discovery source is used."

  validation {
    condition = var.allowed_client_ip == null || (
      can(cidrnetmask("${var.allowed_client_ip}/32")) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.allowed_client_ip)) &&
      !can(regex(
        "^(0\\.|10\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.(0\\.0\\.|0\\.2\\.|168\\.)|198\\.(1[89]\\.|51\\.100\\.)|203\\.0\\.113\\.|(22[4-9]|23[0-9]|24[0-9]|25[0-5])\\.)",
        var.allowed_client_ip
      ))
    )
    error_message = "allowed_client_ip must be null or a public unicast IPv4 address without CIDR notation."
  }
}

variable "enable_core_sql_ai" {
  type        = bool
  default     = true
  description = "Enable the DP-800 Azure SQL AI/RAG stack during later resource modernization."
}

variable "enable_azure_sql_gallery" {
  type        = bool
  default     = true
  description = "Enable Azure SQL Database gallery resources during later resource modernization."
}

variable "enable_sql_managed_instance" {
  type        = bool
  default     = true
  description = "Enable SQL Managed Instance resources during later resource modernization."
}

variable "enable_sql_vm_2019" {
  type        = bool
  default     = true
  description = "Enable SQL Server 2019 virtual machine resources during later resource modernization."
}

variable "enable_sql_vm_2022" {
  type        = bool
  default     = true
  description = "Enable SQL Server 2022 virtual machine resources during later resource modernization."
}

variable "enable_postgresql_flexible" {
  type        = bool
  default     = true
  description = "Enable PostgreSQL Flexible Server resources during later resource modernization."
}

variable "enable_operations" {
  type        = bool
  default     = true
  description = "Enable Database Watcher, Key Vault, and Automation resources during later resource modernization."
}

variable "enable_data_plane" {
  type        = bool
  default     = true
  description = "Enable post-provisioning DP-800 data-plane automation during later resource modernization."
}

# Deprecated compatibility inputs remain until legacy MOD references migrate.
variable "user_name" {
  type        = string
  default     = null
  nullable    = true
  description = "DEPRECATED: legacy alias referenced by existing MOD files. Use admin_username for new configuration."

  validation {
    condition     = var.user_name == null || can(regex("^[A-Za-z][A-Za-z0-9._-]{0,19}$", var.user_name))
    error_message = "user_name must be null or start with a letter and contain at most 20 letters, digits, periods, underscores, or hyphens."
  }
}

variable "user_passowrd" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "DEPRECATED misspelled alias retained only so existing MOD references remain valid. It has no secret default; use admin_password for new configuration."

  validation {
    condition = var.user_passowrd == null || (
      length(var.user_passowrd) >= 12 &&
      length(var.user_passowrd) <= 72 &&
      can(regex("[A-Z]", var.user_passowrd)) &&
      can(regex("[a-z]", var.user_passowrd)) &&
      can(regex("[0-9]", var.user_passowrd)) &&
      can(regex("[^A-Za-z0-9]", var.user_passowrd))
    )
    error_message = "user_passowrd must be null or meet the same 12 to 72 character complexity requirements as admin_password."
  }
}
