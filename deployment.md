# Deployment Guide

How to deploy the AKS landing zone — locally, via GitHub Actions, or via Azure Pipelines.

## 1. Prerequisites

- **Terraform** `>= 1.11` and **Azure CLI** (`az login`).
- Azure RBAC to create resources in the **spoke** and **hub** subscriptions.
- **Directory** permission (e.g. *Groups Administrator*) to create the Entra ID groups (stack `05`).
- Existing hub: Azure Firewall + firewall **policy** (with **DNS Proxy enabled**), hub VNet, and the
  Private DNS zones for ACR / Blob / Key Vault.

> **No hub yet? (testing)** Use the optional `test-hub` stack to create a throwaway hub (VNet +
> AzureFirewallSubnet, Azure Firewall + policy with DNS proxy, and the three Private DNS zones) in
> your own subscription. Apply it after `00-bootstrap`, then copy its outputs into the spoke config
> and set `hub_subscription_id = <your subscription>` (same subscription is fine). See
> [Testing in a single subscription](#testing-in-a-single-subscription).

## 2. One-time bootstrap (state backend)

The remote state storage account is created by `00-bootstrap` using **local** state. Run it once,
manually, before any pipeline:

```bash
cd 00-bootstrap
terraform init
terraform apply
terraform output          # note storage_account_name + resource_group_name
```

Record the outputs — they become the backend config for every other stack.

## 3. Configure variables

Each stack reads a var-file per environment from `config/<environment>/<stack>.tfvars`.
Edit the files under `config/dev/` (or create `config/<env>/`) and fill in your subscription IDs,
hub resource IDs, firewall policy ID, state storage account name, etc.

> These files contain resource IDs (not secrets). Real `*.tfvars` outside `config/` are git-ignored.

## 4. Deploy order

All stacks are applied in this order (bootstrap first, then the rest):

```
00-bootstrap → 05-entra-groups → 10-network → 20-firewall-rules → 30-supporting-services → 40-aks
```

The optional `50-api-management` stack is not part of this sequence. Deploy it separately after the
hub and environment exist.

### Option A — Local / script

```bash
# after editing deploy.azcli variables
bash deploy.azcli
```

Or manually per stack:

```bash
BACKEND=(-backend-config="resource_group_name=<state-rg>"
         -backend-config="storage_account_name=<state-sa>"
         -backend-config="container_name=tfstate")

for STACK in 05-entra-groups 10-network 20-firewall-rules 30-supporting-services 40-aks; do
  terraform -chdir="$STACK" init "${BACKEND[@]}"
  terraform -chdir="$STACK" apply -var-file="config/dev/$STACK.tfvars"
done
```

### Option B — GitHub Actions (`.github/workflows/deploy.yml`)

The workflow uses OIDC and Azure AD backend authentication, so it does not store an Azure client
secret. It supports:

- `plan` on every relevant push to `main` or by manual dispatch.
- `apply` by manual dispatch, using a saved plan for each stack.
- `destroy` by manual dispatch in reverse dependency order. The operator must enter
  `destroy-<environment>` and pass any GitHub environment approval. The state backend is preserved.
- One run per environment at a time, preventing concurrent state operations.

#### One-time Azure identity setup

Create an Entra application or user-assigned identity with a federated credential whose subject is
the GitHub environment:

```text
repo:moselim200@75947258/aks-landing-zone-terrafrom@1379523354:environment:dev
```

Grant the identity:

1. Sufficient RBAC in the spoke subscription to create resources and role assignments.
2. Sufficient RBAC on the hub VNet, firewall policy, IP Group resource group, and Private DNS zones.
3. Microsoft Graph permission to create and manage the two Entra groups in stack
   `05-entra-groups` (for example, `Group.ReadWrite.All` with tenant admin consent).
4. `Storage Blob Data Contributor` on the Terraform state storage account after bootstrap.

#### One-time state bootstrap

Run `00-bootstrap` locally before the first workflow. This stack intentionally remains outside CD
because it uses local state and owns the persistent backend used by every automated stack:

```powershell
az account set --subscription "5f9e50d6-84b3-4c63-af16-737a84d7a3bb"
terraform "-chdir=00-bootstrap" init
terraform "-chdir=00-bootstrap" plan `
  -var-file="../config/dev/00-bootstrap.tfvars" `
  -out="bootstrap.tfplan"
terraform "-chdir=00-bootstrap" apply "bootstrap.tfplan"

terraform "-chdir=00-bootstrap" output
```

#### GitHub environment configuration

Create a protected GitHub environment named `dev`. Add required reviewers for production-like
changes, then configure:

| Type | Name | Value |
|---|---|---|
| Secret | `AZURE_CLIENT_ID` | Client ID of the federated deployment identity |
| Secret | `AZURE_TENANT_ID` | Tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Spoke subscription ID |
| Variable | `TFSTATE_RG` | `00-bootstrap` output `resource_group_name` |
| Variable | `TFSTATE_SA` | `00-bootstrap` output `storage_account_name` |
| Variable | `TFSTATE_CONTAINER` | `00-bootstrap` output `state_container_name` |

Run **Terraform AKS Landing Zone** from GitHub Actions and select `plan` first. Review the plan,
then run `apply`. To remove the managed landing-zone resources, select `destroy` and enter
`destroy-dev`; this does not destroy `00-bootstrap`.

### Option C — Azure Pipelines (`azure-pipelines.yml`)

1. Create an **Azure service connection** with **workload identity federation**, named
   `sc-aks-landing-zone`, scoped to the spoke subscription (with the hub RBAC + directory role).
2. Create a **variable group** `aks-landing-zone` with `TFSTATE_RG`, `TFSTATE_SA`,
   `TFSTATE_CONTAINER`, `ENVIRONMENT`.
3. Run the pipeline and pick the `action` parameter (`plan` or `apply`).

## 5. Connect to the cluster

Members of the admins/developers groups (both have the *Cluster User* role):

```bash
az aks get-credentials --resource-group rg-<prefix>-<env>-aks --name aks-<prefix>-<env>
kubectl get nodes
```

The cluster is private — run from a host with network line-of-sight to the API server, or use
`az aks command invoke`.

## 6. Teardown

Destroy in reverse order (keep `00-bootstrap` last if you still need the state):

```bash
for STACK in 40-aks 30-supporting-services 20-firewall-rules 10-network 05-entra-groups; do
  terraform -chdir="$STACK" destroy -var-file="config/dev/$STACK.tfvars"
done
```

Also destroy `test-hub` if you created it for testing.

## Optional API Management deployment

The `50-api-management` stack deploys one Standard v2 API Management instance in the hub
subscription and region. It also creates a dedicated hub subnet delegated to
`Microsoft.Web/serverFarms`, associates an NSG, and enables outbound VNet integration.

Before deployment:

1. Ensure the `Microsoft.ApiManagement`, `Microsoft.Network`, and `Microsoft.Web` resource
   providers are registered in the hub subscription.
2. Update `config/<environment>/50-api-management.tfvars` with a globally unique APIM name, a real
   publisher email, the hub VNet details, and an unused subnet prefix. A `/24` is recommended and
   `/27` is the minimum.
3. Confirm the APIM instance and hub VNet use the same subscription and region.

Deploy it explicitly:

```bash
terraform -chdir=50-api-management init \
  -backend-config="resource_group_name=<state-rg>" \
  -backend-config="storage_account_name=<state-sa>" \
  -backend-config="container_name=tfstate"

terraform -chdir=50-api-management plan \
  -var-file="../config/<environment>/50-api-management.tfvars"

terraform -chdir=50-api-management apply \
  -var-file="../config/<environment>/50-api-management.tfvars"
```

This integration provides private outbound connectivity to backends in the hub and peered VNets.
Standard v2 gateway, management, and developer portal endpoints remain public.

## Testing in a single subscription

The `test-hub` stack provisions a disposable hub so you can exercise the whole template without an
existing landing zone.

```bash
# after 00-bootstrap, using the same backend config
terraform -chdir=test-hub init "${BACKEND[@]}"
terraform -chdir=test-hub apply -var-file="config/dev/test-hub.tfvars"
terraform -chdir=test-hub output
```

Wire the outputs into the spoke config (`config/dev/*.tfvars`), pointing the hub at the **same**
subscription:

| test-hub output | Used by | Variable |
|---|---|---|
| `hub_virtual_network_id` | 10-network | `hub_virtual_network_id` |
| `hub_virtual_network_name` | 10-network | `hub_virtual_network_name` |
| `hub_network_resource_group_name` | 10-network | `hub_network_resource_group_name` |
| `hub_firewall_private_ip` | 10-network | `hub_firewall_private_ip` |
| `hub_private_dns_zones` | 10-network | `hub_private_dns_zones` |
| `firewall_policy_id` | 20-firewall-rules | `firewall_policy_id` |
| `hub_network_resource_group_name` | 20-firewall-rules | `ip_group_resource_group_name` |
| `hub_private_dns_zone_ids` | 30-supporting-services | `hub_private_dns_zone_ids` |

Set `hub_subscription_id = <your subscription>` (equal to `spoke_subscription_id`) in the 10-network
and 20-firewall-rules configs. Then deploy the stacks in the normal order.
