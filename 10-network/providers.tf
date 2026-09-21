terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81, < 5.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Default provider: spoke (application landing zone) subscription.
provider "azurerm" {
  features {}
  subscription_id = var.spoke_subscription_id
}

# Aliased provider: hub / Azure landing zone subscription.
# Used for the hub side of the peering and the Private DNS zone VNet links.
provider "azurerm" {
  alias = "hub"
  features {}
  subscription_id = var.hub_subscription_id
}
