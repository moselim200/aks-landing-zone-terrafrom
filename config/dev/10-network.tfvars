spoke_subscription_id = "5f9e50d6-84b3-4c63-af16-737a84d7a3bb"
hub_subscription_id   = "285d725f-e15b-4ee1-9070-8da287e27bde"
location              = "swedencentral"
prefix                = "aks"
environment           = "dev"

hub_virtual_network_id          = "/subscriptions/285d725f-e15b-4ee1-9070-8da287e27bde/resourceGroups/rg-hub-swedencentral/providers/Microsoft.Network/virtualNetworks/vnet-hub-swedencentral"
hub_virtual_network_name        = "vnet-hub-swedencentral"
hub_network_resource_group_name = "rg-hub-swedencentral"
hub_firewall_private_ip         = "10.0.0.4"

hub_private_dns_zones = {
  acr      = { name = "privatelink.azurecr.io", resource_group_name = "rg-hub-dns-swedencentral" }
  blob     = { name = "privatelink.blob.core.windows.net", resource_group_name = "rg-hub-dns-swedencentral" }
  keyvault = { name = "privatelink.vaultcore.azure.net", resource_group_name = "rg-hub-dns-swedencentral" }
}
