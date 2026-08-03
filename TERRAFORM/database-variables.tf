variable "enable_legacy_key_auth_demo" {
  type        = bool
  default     = false
  description = "Enable legacy storage-key authentication only for the SQL VM automated-backup and auditing demonstrations. The default path uses managed identity and RBAC."
}

variable "enable_azure_services_firewall_demo" {
  type        = bool
  default     = true
  description = "Allow Azure-hosted demo services, including Azure Automation, to reach Azure SQL. This broad Azure boundary is enabled only for the course operations demonstration."
}
