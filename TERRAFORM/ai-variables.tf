variable "ai_sql_database_name" {
  type        = string
  default     = "dp800-ai-rag"
  description = "Name of the independent Azure SQL Database used by DP-800 modules 09 through 11."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,126}$", var.ai_sql_database_name))
    error_message = "ai_sql_database_name must be 1 to 127 letters, digits, underscores, or hyphens."
  }
}

variable "ai_sql_database_sku" {
  type        = string
  default     = "GP_S_Gen5_2"
  description = "Azure SQL Database serverless General Purpose SKU used for SQL-native vector and AI labs."

  validation {
    condition     = var.ai_sql_database_sku == "GP_S_Gen5_2"
    error_message = "This course stack validates SQL-native AI features with the official GP_S_Gen5_2 SKU."
  }
}

variable "ai_entra_admin_login" {
  type        = string
  default     = "dp800-entra-admin"
  description = "Display name assigned to the Azure SQL Microsoft Entra administrator object."

  validation {
    condition     = length(trimspace(var.ai_entra_admin_login)) > 0
    error_message = "ai_entra_admin_login must not be empty."
  }
}

variable "ai_embedding_deployment_name" {
  type        = string
  default     = "text-embedding-3-small"
  description = "Azure OpenAI embedding deployment name referenced by CREATE EXTERNAL MODEL."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", var.ai_embedding_deployment_name))
    error_message = "ai_embedding_deployment_name must be 1 to 64 deployment-safe characters."
  }
}

variable "ai_embedding_model_name" {
  type        = string
  default     = "text-embedding-3-small"
  description = "Embedding model fixed to the 1536-dimensional model used by the course SQL schema."

  validation {
    condition     = var.ai_embedding_model_name == "text-embedding-3-small"
    error_message = "The course SQL schema requires text-embedding-3-small with 1536-dimensional vectors."
  }
}

variable "ai_embedding_model_version" {
  type        = string
  default     = "1"
  description = "Embedding model version validated against official availability on 2026-08-03."

  validation {
    condition     = var.ai_embedding_model_version == "1"
    error_message = "The validated text-embedding-3-small deployment uses model version 1."
  }
}

variable "ai_embedding_model_sku" {
  type        = string
  default     = "GlobalStandard"
  description = "Embedding deployment SKU validated for Japan East on 2026-08-03."

  validation {
    condition     = contains(["Standard", "GlobalStandard", "DataZoneStandard"], var.ai_embedding_model_sku)
    error_message = "ai_embedding_model_sku must be Standard, GlobalStandard, or DataZoneStandard."
  }
}

variable "ai_embedding_model_capacity" {
  type        = number
  default     = 10
  description = "Embedding deployment capacity in thousands of tokens per minute."

  validation {
    condition     = var.ai_embedding_model_capacity >= 1
    error_message = "ai_embedding_model_capacity must be at least 1."
  }
}

variable "ai_chat_deployment_name" {
  type        = string
  default     = "gpt-5.4-mini"
  description = "Azure OpenAI chat deployment name used by the SQL-native RAG procedure."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", var.ai_chat_deployment_name))
    error_message = "ai_chat_deployment_name must be 1 to 64 deployment-safe characters."
  }
}

variable "ai_chat_model_name" {
  type        = string
  default     = "gpt-5.4-mini"
  description = "GA chat model validated against official lifecycle and availability on 2026-08-03."
}

variable "ai_chat_model_version" {
  type        = string
  default     = "2026-03-17"
  description = "Chat model version validated against official lifecycle and availability on 2026-08-03."
}

variable "ai_chat_model_sku" {
  type        = string
  default     = "GlobalStandard"
  description = "Chat deployment SKU validated for Japan East on 2026-08-03."

  validation {
    condition     = var.ai_chat_model_sku == "GlobalStandard"
    error_message = "The selected gpt-5.4-mini course deployment is validated with GlobalStandard."
  }
}

variable "ai_chat_model_capacity" {
  type        = number
  default     = 10
  description = "Chat deployment capacity in thousands of tokens per minute."

  validation {
    condition     = var.ai_chat_model_capacity >= 1
    error_message = "ai_chat_model_capacity must be at least 1."
  }
}
