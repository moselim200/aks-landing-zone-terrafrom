spoke_subscription_id = "5f9e50d6-84b3-4c63-af16-737a84d7a3bb"
location              = "swedencentral"
prefix                = "aks"
environment           = "dev"

state_resource_group_name  = "rg-aks-dev-tfstate"
state_storage_account_name = "staksdevtfvs1mu"
state_container_name       = "tfstate"

kubernetes_version    = null
private_dns_zone_mode = "system"

# Testing: also expose a public FQDN for the private API server so kubectl works
# from your machine without a jumpbox. Set back to false for strict-private.
enable_private_cluster_public_fqdn = true

# Entra group object IDs granted cluster-admin. Leave empty to use the group
# created by 05-entra-groups (wired automatically), or add extra admin groups here.
admin_group_object_ids = []

system_node_vm_size = "Standard_D2ds_v5"
user_node_vm_size   = "Standard_D2ds_v5"

system_node_min = 1
system_node_max = 2
user_node_min   = 1
user_node_max   = 3
