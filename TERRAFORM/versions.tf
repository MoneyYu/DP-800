terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.1, < 6.0.0"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.11"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }
}
