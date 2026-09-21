terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81, < 5.0"
    }
  }
}

# Default provider: spoke subscription (used for the remote-state backend context).
provider "azurerm" {
  features {}
  subscription_id = var.spoke_subscription_id
}

# Hub / Azure landing zone subscription: the existing firewall policy and IP Group live here.
provider "azurerm" {
  alias = "hub"
  features {}
  subscription_id                 = var.hub_subscription_id
  resource_provider_registrations = "none"
}
