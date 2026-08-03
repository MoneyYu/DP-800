provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  resource_providers_to_register = [
    "Microsoft.Automation",
    "Microsoft.CognitiveServices",
    "Microsoft.Compute",
    "Microsoft.DatabaseWatcher",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Sql",
    "Microsoft.Storage",
  ]
}

data "azurerm_client_config" "current" {}

# Keep this uncounted data source until legacy MOD files migrate from
# data.http.myip.response_body to local.effective_allowed_client_ip.
data "http" "myip" {
  url = "https://api.ipify.org"

  request_headers = {
    Accept = "text/plain"
  }
}

resource "random_string" "rid" {
  length  = 3
  special = false
  numeric = false
  upper   = false
}

# The Terraform label remains dp300 until the database resources and state are
# migrated together. Renaming it now would change every legacy MOD reference.
resource "azurerm_resource_group" "dp300" {
  name     = local.group_name
  location = local.location

  tags = local.default_tags
}
