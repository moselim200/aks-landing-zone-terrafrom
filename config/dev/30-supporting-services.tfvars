spoke_subscription_id = "5f9e50d6-84b3-4c63-af16-737a84d7a3bb"
location              = "swedencentral"
prefix                = "aks"
environment           = "dev"

# Testing: allow public network access to ACR / Storage / Key Vault so you can push
# images and read secrets from your machine. Private endpoints are still created.
# Set back to false for production.
public_network_access_enabled = false

state_resource_group_name  = "rg-aks-dev-tfstate"
state_storage_account_name = "staksdevtfvs1mu"
state_container_name       = "tfstate"

hub_private_dns_zone_ids = {
  acr      = "/subscriptions/285d725f-e15b-4ee1-9070-8da287e27bde/resourceGroups/rg-hub-dns-swedencentral/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  blob     = "/subscriptions/285d725f-e15b-4ee1-9070-8da287e27bde/resourceGroups/rg-hub-dns-swedencentral/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  keyvault = "/subscriptions/285d725f-e15b-4ee1-9070-8da287e27bde/resourceGroups/rg-hub-dns-swedencentral/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
}
