data "azurerm_client_config" "current" {}

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

data "terraform_remote_state" "supporting" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "30-supporting-services.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "entra" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "05-entra-groups.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  tags                = merge(var.tags, { environment = var.environment })
  name                = "${var.prefix}-${var.environment}"
  aks_subnet_id       = data.terraform_remote_state.network.outputs.subnet_ids["aks"]
  network_rg_name     = data.terraform_remote_state.network.outputs.resource_group_name
  network_rg_id       = "/subscriptions/${var.spoke_subscription_id}/resourceGroups/${local.network_rg_name}"
  uami_id             = data.terraform_remote_state.supporting.outputs.uami_id
  uami_principal_id   = data.terraform_remote_state.supporting.outputs.uami_principal_id
  admins_group_id     = data.terraform_remote_state.entra.outputs.admins_group_object_id
  developers_group_id = data.terraform_remote_state.entra.outputs.developers_group_object_id
}

resource "azurerm_resource_group" "aks" {
  name     = "rg-${local.name}-aks"
  location = var.location
  tags     = local.tags
}

# The cluster identity (UAMI) needs to manage the LB and join the AKS subnet.
resource "azurerm_role_assignment" "network_contributor" {
  scope                = local.network_rg_id
  role_definition_name = "Network Contributor"
  principal_id         = local.uami_principal_id
  principal_type       = "ServicePrincipal"
}

# Required to reuse the same UAMI as the kubelet identity.
resource "azurerm_role_assignment" "mi_operator" {
  scope                = local.uami_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = local.uami_principal_id
  principal_type       = "ServicePrincipal"
}

module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.8.3"

  name      = "aks-${local.name}"
  location  = azurerm_resource_group.aks.location
  parent_id = azurerm_resource_group.aks.id
  tags      = local.tags

  kubernetes_version  = var.kubernetes_version
  dns_prefix          = "${local.name}-aks"
  node_resource_group = "rg-${local.name}-aks-nodes"

  sku = {
    name = "Base"
    tier = "Free"
  }

  # Bring-your-own identity for both control plane and kubelet.
  managed_identities = {
    system_assigned            = false
    user_assigned_resource_ids = [local.uami_id]
  }
  identity_profile = {
    kubeletidentity = {
      resource_id = local.uami_id
    }
  }

  # Entra RBAC, no local admin accounts.
  aad_profile = {
    managed                = true
    enable_azure_rbac      = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = concat(var.admin_group_object_ids, [local.admins_group_id])
  }
  disable_local_accounts = true

  # OIDC + Workload Identity.
  oidc_issuer_profile = {
    enabled = true
  }
  security_profile = {
    workload_identity = {
      enabled = true
    }
    image_cleaner = {
      enabled        = true
      interval_hours = 48
    }
  }

  # Private cluster with AKS-managed (system) API server DNS zone.
  api_server_access_profile = {
    enable_private_cluster             = true
    enable_private_cluster_public_fqdn = var.enable_private_cluster_public_fqdn
    private_dns_zone                   = var.private_dns_zone_mode
  }

  # CNI Overlay + Cilium dataplane, egress via the hub firewall (UDR).
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_dataplane   = "cilium"
    outbound_type       = "userDefinedRouting"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
  }

  # System node pool (tainted for system workloads).
  default_agent_pool = {
    name                = "systempool"
    vm_size             = var.system_node_vm_size
    vnet_subnet_id      = local.aks_subnet_id
    availability_zones  = var.availability_zones
    os_sku              = "AzureLinux"
    os_disk_size_gb     = 64
    os_disk_type        = "Ephemeral"
    enable_auto_scaling = true
    min_count           = var.system_node_min
    max_count           = var.system_node_max
    count_of            = var.system_node_min
    max_pods            = 50
    node_taints         = ["CriticalAddonsOnly=true:NoSchedule"]
    upgrade_settings = {
      max_surge = "33%"
    }
  }

  # User (workload) node pool.
  agent_pools = {
    userpool = {
      name                = "userpool"
      mode                = "User"
      type                = "VirtualMachineScaleSets"
      vm_size             = var.user_node_vm_size
      vnet_subnet_id      = local.aks_subnet_id
      availability_zones  = var.availability_zones
      os_sku              = "AzureLinux"
      os_disk_size_gb     = 64
      os_disk_type        = "Ephemeral"
      enable_auto_scaling = true
      min_count           = var.user_node_min
      max_count           = var.user_node_max
      max_pods            = 50
      upgrade_settings = {
        max_surge = "33%"
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.network_contributor,
    azurerm_role_assignment.mi_operator,
  ]
}

# ---------------------------------------------------------------------------
# Cluster access (Azure RBAC for Kubernetes).
# Admins get cluster-admin via aad_profile.admin_group_object_ids above.
# Both groups need "Cluster User" to pull kubeconfig; developers get namespace
# read/write via the RBAC Writer role.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "admins_cluster_user" {
  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = local.admins_group_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "developers_cluster_user" {
  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = local.developers_group_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "developers_rbac_writer" {
  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = local.developers_group_id
  principal_type       = "Group"
}
