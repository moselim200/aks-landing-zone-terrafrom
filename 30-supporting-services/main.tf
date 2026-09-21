data "azurerm_client_config" "current" {}

# Network stack outputs (spoke VNet + subnet IDs) via remote state.
data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "10-network.tfstate"
    use_azuread_auth     = true
  }
}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  tags         = merge(var.tags, { environment = var.environment })
  name         = "${var.prefix}-${var.environment}"
  pe_subnet_id = data.terraform_remote_state.network.outputs.subnet_ids["privateendpoints"]
  suffix       = random_string.suffix.result
  acr_name     = "acr${var.prefix}${var.environment}${local.suffix}"
  sa_name      = "st${var.prefix}${var.environment}${local.suffix}"
  kv_name      = "kv-${var.prefix}-${var.environment}-${local.suffix}"
  uami_name    = "id-${local.name}-aks"
}

resource "azurerm_resource_group" "supporting" {
  name     = "rg-${local.name}-supporting"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# User-assigned managed identity (AKS kubelet / workload identity anchor).
# ---------------------------------------------------------------------------
module "uami" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.2"

  name                = local.uami_name
  location            = azurerm_resource_group.supporting.location
  resource_group_name = azurerm_resource_group.supporting.name
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry (Premium, private endpoint, AcrPull for the UAMI).
# ---------------------------------------------------------------------------
module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.8.0"

  name                = local.acr_name
  location            = azurerm_resource_group.supporting.location
  resource_group_name = azurerm_resource_group.supporting.name
  sku                 = "Premium"
  tags                = local.tags

  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = true

  private_endpoints = {
    registry = {
      name                          = "pe-${local.acr_name}"
      subnet_resource_id            = local.pe_subnet_id
      private_dns_zone_resource_ids = [var.hub_private_dns_zone_ids.acr]
    }
  }

  role_assignments = {
    aks_acrpull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = module.uami.principal_id
      principal_type             = "ServicePrincipal"
    }
  }
}

# ---------------------------------------------------------------------------
# Storage account (private blob endpoint, key access disabled).
# ---------------------------------------------------------------------------
module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  name      = local.sa_name
  location  = azurerm_resource_group.supporting.location
  parent_id = azurerm_resource_group.supporting.id
  tags      = local.tags

  account_kind              = "StorageV2"
  account_replication_type  = "ZRS"
  shared_access_key_enabled = false

  public_network_access_enabled = var.public_network_access_enabled

  network_rules = {
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }

  private_endpoints = {
    blob = {
      name                          = "pe-${local.sa_name}-blob"
      subnet_resource_id            = local.pe_subnet_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [var.hub_private_dns_zone_ids.blob]
    }
  }
}

# ---------------------------------------------------------------------------
# Key Vault (RBAC, private endpoint, Secrets User for the UAMI / CSI driver).
# ---------------------------------------------------------------------------
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = local.kv_name
  location            = azurerm_resource_group.supporting.location
  resource_group_name = azurerm_resource_group.supporting.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  purge_protection_enabled      = true
  public_network_access_enabled = var.public_network_access_enabled

  network_acls = {
    bypass         = "AzureServices"
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
  }

  private_endpoints = {
    vault = {
      name                          = "pe-${local.kv_name}"
      subnet_resource_id            = local.pe_subnet_id
      private_dns_zone_resource_ids = [var.hub_private_dns_zone_ids.keyvault]
    }
  }

  role_assignments = {
    aks_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.uami.principal_id
      principal_type             = "ServicePrincipal"
    }
  }
}
