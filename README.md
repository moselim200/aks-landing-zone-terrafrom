# AKS Landing Zone (Terraform)

Infrastructure-as-code for a **private Azure Kubernetes Service (AKS) landing zone**, built with
[Azure Verified Modules](https://aka.ms/avm) and organized as small, independently applied
Terraform stacks.

The spoke (application landing zone) lives in one subscription; the hub / Azure landing zone
(Azure Firewall + policy, hub VNet, Private DNS zones) lives in a **separate** subscription.
Terraform reaches the hub through an aliased provider.

## Architecture

- **Spoke VNet** `10.116.12.0/22` with four subnets: AKS nodes, data, private endpoints, and a
  reserved App Gateway / AGC subnet. NSGs per subnet and a UDR that forces AKS egress through the
  hub Azure Firewall.
- **Firewall rules** appended to the **existing** hub firewall policy, using an **IP Group** for the
  AKS egress sources (update sources without touching rules). No wildcard network destinations.
- **Supporting services** — ACR (Premium), Storage, Key Vault, and a user-assigned managed identity
  — all reachable only via **private endpoints** into the hub Private DNS zones. A
  `public_network_access_enabled` toggle allows temporary public access for testing.
- **AKS** — Standard tier, **private cluster**, **Azure CNI Overlay + Cilium**, egress via
  `userDefinedRouting`, OIDC + Workload Identity, Entra RBAC, local accounts disabled. The
  supporting UAMI is used as both control-plane and kubelet identity.
- **Entra ID groups** — `admins` (cluster-admin) and `developers` (namespace read/write) bound to
  the cluster via Azure RBAC for Kubernetes.

## Repository layout

Each folder is a standalone Terraform stack with its own remote-state key.

| Stack | Purpose |
|-------|---------|
| `00-bootstrap` | Resource group + storage account/container that hold the Terraform remote state. |
| `05-entra-groups` | Entra ID security groups: AKS admins and developers. |
| `10-network` | Spoke VNet, 4 subnets, NSGs, UDR, hub peering (both directions), Private DNS zone links. |
| `20-firewall-rules` | IP Group + rule collection group added to the existing hub firewall policy. |
| `30-supporting-services` | ACR, Storage, Key Vault, user-assigned managed identity (all private). |
| `40-aks` | Private AKS cluster (overlay + Cilium, UDR, Workload Identity) and cluster RBAC. |
| `50-api-management` | Optional API Management Standard v2 instance with outbound integration to a dedicated hub subnet. |
| `deploy.azcli` | Simple Azure CLI + bash script that logs in and applies every stack in order. |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.11`
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (logged in: `az login`)
- Azure RBAC to create resources in **both** the spoke and hub subscriptions.
- **Directory** permission (e.g. *Groups Administrator*) to create the Entra ID groups (stack `05`).
- An existing hub with: Azure Firewall + firewall **policy**, hub VNet, and Private DNS zones for
  `privatelink.azurecr.io`, `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`.
- **DNS Proxy enabled** on the hub firewall policy (required by the NTP FQDN network rule).

## Configuration

Every stack ships a `terraform.tfvars.example`. Copy it and fill in your values:

```bash
cp 10-network/terraform.tfvars.example 10-network/terraform.tfvars
```

Real `*.tfvars` and state files are git-ignored.

## Deploy

Apply the stacks in order. `00-bootstrap` creates the state storage account; the remaining stacks
store their state there and read each other's outputs.

```bash
# 1) State backend (local state, kept in the repo folder for this stack only)
terraform -chdir=00-bootstrap init
terraform -chdir=00-bootstrap apply
#    Note the storage_account_name output for the next steps.

# 2) Remaining stacks (remote state in the bootstrap storage account)
BACKEND=(-backend-config="resource_group_name=<state-rg>"
         -backend-config="storage_account_name=<state-sa>"
         -backend-config="container_name=tfstate")

for STACK in 05-entra-groups 10-network 20-firewall-rules 30-supporting-services 40-aks; do
  terraform -chdir="$STACK" init "${BACKEND[@]}"
  terraform -chdir="$STACK" apply
done
```

Or use the helper script after editing its variables:

```bash
bash deploy.azcli
```

For automated plan, apply, and guarded reverse-order destroy operations, use
`.github/workflows/deploy.yml`. The Terraform state backend is bootstrapped once and deliberately
preserved during automated destroy. See [Deployment Guide](deployment.md#option-b--github-actions-githubworkflowsdeployyml)
for the OIDC identity, GitHub environment, and required variables.

### Optional API Management

API Management is intentionally excluded from the default deployment loop. After the environment
and hub are available, configure `config/<environment>/50-api-management.tfvars`, including a real
publisher email and an unused `/24` in the hub VNet, then deploy the standalone stack:

```bash
terraform -chdir=50-api-management init "${BACKEND[@]}"
terraform -chdir=50-api-management plan \
  -var-file="../config/dev/50-api-management.tfvars"
terraform -chdir=50-api-management apply \
  -var-file="../config/dev/50-api-management.tfvars"
```

Standard v2 VNet integration is outbound only: APIM can reach private backends in the hub and
peered networks, while its gateway, management, and developer portal endpoints remain public.

## Connect to the cluster

Members of the admins/developers groups can fetch credentials (both groups have the *Cluster User*
role):

```bash
az aks get-credentials --resource-group rg-<prefix>-<env>-aks --name aks-<prefix>-<env>
kubectl get nodes
```

Because the cluster is private, run this from a host with network line-of-sight to the API server
(e.g. a jumpbox in the hub/spoke) or via `az aks command invoke`.

## Notes

- Set `public_network_access_enabled = true` in `30-supporting-services` only for temporary testing;
  keep it `false` for private-only access.
- To allow additional egress sources later, update `aks_egress_source_cidrs` in `20-firewall-rules`
  — the IP Group changes without editing any rule.
- To add workload-specific egress FQDNs, use `extra_allowed_fqdns` in `20-firewall-rules`.
