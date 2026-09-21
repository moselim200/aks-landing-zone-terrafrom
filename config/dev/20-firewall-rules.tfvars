spoke_subscription_id = "5f9e50d6-84b3-4c63-af16-737a84d7a3bb"
hub_subscription_id   = "285d725f-e15b-4ee1-9070-8da287e27bde"
location              = "swedencentral"
prefix                = "aks"
environment           = "dev"

firewall_policy_id           = "/subscriptions/285d725f-e15b-4ee1-9070-8da287e27bde/resourceGroups/rg-hub-swedencentral/providers/Microsoft.Network/firewallPolicies/fwp-hub-swedencentral"
ip_group_resource_group_name = "rg-hub-swedencentral"
aks_egress_source_cidrs      = ["10.116.12.0/24"]

# Optional (defaults shown):
# rule_collection_group_priority = 500
# extra_allowed_fqdns            = []
