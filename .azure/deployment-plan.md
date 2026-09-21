# Azure Deployment Plan

> **Status:** Validated

Generated: 2026-09-21T13:55:22+03:00

---

## 1. Project Overview

**Goal:** Deploy the existing private AKS landing zone and automate plan, apply, and guarded
reverse-order destroy operations with GitHub Actions and passwordless Azure OIDC authentication.

**Path:** Modify an existing Terraform project.

The persistent Terraform state backend is created once from a trusted local workstation and is
deliberately preserved by automated destroy operations.

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | Proof of concept |
| Scale | Small, under 1,000 users |
| Budget | Cost-optimized |
| Spoke subscription | LandingZone-moselim-4 (`5f9e50d6-84b3-4c63-af16-737a84d7a3bb`) |
| Hub subscription | Connectivity-moselim-3 (`285d725f-e15b-4ee1-9070-8da287e27bde`) |
| Location | Sweden Central (`swedencentral`) |
| Data residency | Sweden Central |
| Additional compliance | None beyond private networking and regional residency |
| Resource prefix | `aks` |
| Environment | `dev` |

### Policy Constraints

The spoke subscription has two inherited Defender initiatives for open-source relational databases
and SQL Servers on Machines. Neither targets the resource types in this deployment. No deny policy
affecting AKS, networking, Storage, ACR, Key Vault, or managed identities was discovered.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| State backend | Terraform stack | Azure Storage with Azure AD auth | `00-bootstrap` |
| Cluster groups | Identity stack | Microsoft Entra ID | `05-entra-groups` |
| Spoke networking | Network stack | VNet, NSGs, UDR, peering, DNS links | `10-network` |
| AKS egress | Firewall stack | Azure Firewall policy and IP Group | `20-firewall-rules` |
| Platform services | Supporting stack | ACR, Storage, Key Vault, managed identity | `30-supporting-services` |
| Kubernetes platform | Compute stack | Private AKS with Cilium and workload identity | `40-aks` |
| Continuous delivery | Automation | GitHub Actions with Azure OIDC | `.github/workflows/deploy.yml` |

The optional `test-hub` and `50-api-management` stacks are out of scope.

---

## 4. Recipe Selection

**Selected:** Pure Terraform.

**Rationale:** The repository already consists of ordered, independently stateful Terraform stacks
using Azure Verified Modules. Converting it to azd would introduce an unnecessary orchestration
layer and state migration risk. Deployment order is:

```text
00-bootstrap (one time, local state)
  -> 05-entra-groups
  -> 10-network
  -> 20-firewall-rules
  -> 30-supporting-services
  -> 40-aks
```

Automated destroy reverses the five remote-state stacks and never destroys `00-bootstrap`.

---

## 5. Architecture

**Stack:** Private Kubernetes landing zone with hub-spoke networking.

### Service Mapping

| Component | Azure Service | SKU/configuration |
|-----------|---------------|-------------------|
| Cluster | Azure Kubernetes Service | Base/Free tier for POC |
| System node pool | Virtual Machine Scale Sets | `Standard_D2ds_v5`, min 1, max 2 |
| User node pool | Virtual Machine Scale Sets | `Standard_D2ds_v5`, min 1, max 3 |
| Container registry | Azure Container Registry | Premium, private endpoint |
| Secrets | Azure Key Vault | Standard, RBAC, purge protection, private endpoint |
| Application storage | Azure Storage | Standard ZRS, private endpoint |
| Terraform state | Azure Storage | Standard LRS, versioning and retention |
| Egress | Existing Azure Firewall | `fw-hub-swedencentral`, private IP `10.0.0.4` |
| Firewall policy | Existing Azure Firewall Policy | `fwp-hub-swedencentral`, DNS proxy enabled |

### Network Mapping

| Network | CIDR / resource |
|---------|-----------------|
| Existing hub | `vnet-hub-swedencentral`, `10.0.0.0/22` |
| New spoke | `vnet-aks-dev-spoke`, `10.116.12.0/22` |
| AKS subnet | `10.116.12.0/24` |
| Data subnet | `10.116.13.0/25` |
| Private endpoint subnet | `10.116.13.128/25` |
| Reserved application gateway subnet | `10.116.14.0/24` |
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.245.0.0/24` |

No overlap was found with the selected hub or existing spoke VNets. The AKS API remains private;
the public FQDN option is enabled for name resolution but does not create a public API endpoint.
ACR, Storage, and Key Vault public network access remains disabled.

---

## 6. Provisioning Limit Checklist

Quota source: Azure Quota CLI on 2026-09-21 for subscription
`5f9e50d6-84b3-4c63-af16-737a84d7a3bb` in `swedencentral`.

| Resource type | Number to deploy | Total after deployment | Limit/quota | Notes |
|---------------|------------------|------------------------|-------------|-------|
| Regional vCPUs | Up to 10 | 20 | 100 | Current usage 10; `cores` quota |
| Standard DDSv5 family vCPUs | Up to 10 | 10 | 100 | Current usage 0; `standardDDSv5Family` quota |
| AKS managed clusters | 1 | 2 | 50 | Current usage 1; `ManagedClusters` quota |
| Virtual networks | 1 | 3 | 1,000 | Current usage 2; `VirtualNetworks` quota |
| Network security groups | 4 | 6 | 5,000 | Current usage 2; `NetworkSecurityGroups` quota |
| Route tables | 1 | 1 | 600 | Current usage 0; `RouteTables` quota |
| Private endpoints | 3 | 3 | 65,536 | Current usage 0; `PrivateEndpoints` quota |
| Storage accounts | 2 | 2 | 250 | Current usage 0; `StorageAccounts` quota |
| Azure Container Registry | 1 | 1 | N/A | No regional quota entry; provider registered |
| Key Vault | 1 | 1 | N/A | No regional quota entry; provider registered |
| User-assigned managed identities | 1 | 4 | N/A | Three currently exist; no regional quota entry |
| Resource groups | 4 explicit + 1 AKS-managed | Within subscription limit | 980 | Standard Azure subscription limit |
| Entra security groups | 2 | Within tenant limit | N/A | Created through Microsoft Graph |
| Firewall rule collection groups | 1 | 1 new | N/A | No existing groups or priority-500 conflict |

**Status:** All checked resources are within limits. `Standard_D2ds_v5` is available without
restrictions in availability zones 1, 2, and 3 and supports ephemeral OS disks.

---

## 7. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace
- [x] Gather classification, scale, budget, and compliance requirements
- [x] Confirm subscriptions and location with the user
- [x] Inspect Azure Policy assignments
- [x] Prepare resource inventory
- [x] Fetch quotas and validate capacity with Azure Quota CLI
- [x] Scan the Terraform stacks and dependency order
- [x] Select the pure Terraform recipe
- [x] Plan architecture and CD controls
- [x] User approved this plan

### Phase 2: Preparation

- [x] Configure passwordless Entra application and GitHub federated credential
- [x] Grant and verify scoped Azure RBAC
- [x] Grant and verify Microsoft Graph `Group.ReadWrite.All`
- [x] Create the GitHub `dev` environment and configure known OIDC values
- [x] Create guarded GitHub Actions plan/apply/destroy workflow
- [x] Apply cost-optimized AKS Free-tier and node-pool settings
- [x] Run Terraform formatting and validation
- [x] Update status to `Ready for Validation`

### Phase 3: Validation

- [x] Run the Azure validation workflow
- [x] All validation checks pass
  - [x] Terraform CLI and Azure CLI are installed
  - [x] Azure CLI is authenticated to the confirmed tenant and spoke subscription
  - [x] Terraform formatting passes repository-wide
  - [x] All six Terraform stacks initialize and validate
  - [x] No unresolved Go-template placeholders exist in the Terraform configuration
  - [x] GitHub Actions workflow passes `actionlint`
  - [x] Azure Policy assignments have no blocking constraints
  - [x] Regional compute, AKS, network, and storage quotas have sufficient capacity
  - [x] Saved `00-bootstrap` Terraform plan succeeds without destructive changes
- [x] Set status to `Validated` and populate validation proof

### Phase 4: Deployment

- [x] Apply the approved bootstrap plan
- [x] Grant the OIDC identity `Storage Blob Data Contributor` on state storage
- [x] Set GitHub environment variable `TFSTATE_SA`
- [ ] Push the pipeline and configuration to the fork
- [ ] Run the GitHub Actions `plan` operation
- [ ] Review the remote plan
- [ ] Run `apply` only after explicit approval
- [ ] Verify AKS provisioning and node readiness
- [ ] Set status to `Deployed`

---

## 8. Validation Proof

> This section must be populated by the Azure validation workflow before deployment.

| Check | Command run | Result | Timestamp |
|-------|-------------|--------|-----------|
| Tooling | `terraform version`; `az version`; `az account show` | Pass: Terraform 1.16.2, Azure CLI 2.89.0, authenticated tenant | 2026-09-21 |
| Terraform formatting | `terraform fmt -check -recursive` | Pass | 2026-09-21 |
| Terraform schemas | `terraform init -backend=false` and `terraform validate` for all six stacks | Pass: all stacks valid | 2026-09-21 |
| Workflow syntax | `actionlint .github/workflows/deploy.yml` | Pass | 2026-09-21 |
| Policy constraints | `az policy assignment list --subscription LandingZone-moselim-4 --disable-scope-strict-match` | Pass: no blocking policies found | 2026-09-21 |
| Compute quota | Azure Quota CLI for `cores` and `standardDDSv5Family` | Pass: 90 regional and 100 family vCPUs available | 2026-09-21 |
| Network quota | Azure Quota CLI for VNets, NSGs, route tables, and private endpoints | Pass: sufficient capacity | 2026-09-21 |
| Storage quota | Azure Quota CLI for `StorageAccounts` | Pass: 250 available | 2026-09-21 |
| AKS quota | Azure Quota CLI for `ManagedClusters` | Pass: 49 available | 2026-09-21 |
| VM SKU | `az vm list-skus --location swedencentral --size Standard_D2ds_v5 --all` | Pass: zones 1-3, ephemeral OS disk supported, no restrictions | 2026-09-21 |
| Hub collision | Azure REST query for firewall policy rule collection groups | Pass: no name or priority-500 conflict | 2026-09-21 |
| Static RBAC | Review of all Terraform role assignments | Pass: required roles and scopes present | 2026-09-21 |
| Bootstrap plan | `terraform -chdir=00-bootstrap plan -var-file=../config/dev/00-bootstrap.tfvars -out=../.azure/bootstrap.tfplan` | Pass: 4 create, 0 change, 0 destroy | 2026-09-21 |
| Initial CD plan | GitHub Actions run `35593149602` | Identified expected absent upstream state for downstream stacks; workflow updated to skip only dependency-blocked plans | 2026-09-21 |

**Validated by:** Azure validation workflow

**Validation timestamp:** 2026-09-21

---

## 9. Security and Identity

- GitHub Actions authenticates through OIDC; no client secret is stored.
- Deployment identity: `github-aks-landing-zone-dev`
  (`6f386c64-5ad4-4454-8b57-8a8cdb6ae3cf`).
- Federated subject:
  `repo:moselim200@75947258/aks-landing-zone-terrafrom@1379523354:environment:dev`.
- Spoke permissions: Contributor and User Access Administrator.
- Hub permissions: Contributor only on `rg-hub-swedencentral` and
  `rg-hub-dns-swedencentral`.
- Directory permission: `Group.ReadWrite.All` application role with admin consent.
- Supporting services use private endpoints and managed identities.
- Terraform state uses Azure AD authentication, blob versioning, and retention.
- GitHub destroy requires manual dispatch, the exact `destroy-dev` confirmation, serialized
  execution, and the `dev` environment gate.

### Static Role Assignment Verification

**Status:** Verified.

| Principal | Role | Scope | Purpose |
|-----------|------|-------|---------|
| AKS user-assigned identity | `AcrPull` | Generated ACR | Pull workload images |
| AKS user-assigned identity | `Key Vault Secrets User` | Generated Key Vault | Read secrets through the CSI/workload path |
| AKS user-assigned identity | `Network Contributor` | Spoke network resource group | Join the AKS subnet and manage load-balancer networking |
| AKS user-assigned identity | `Managed Identity Operator` | AKS user-assigned identity | Reuse the identity as the kubelet identity |
| Admins Entra group | `Azure Kubernetes Service Cluster User Role` | Generated AKS cluster | Fetch user kubeconfig |
| Developers Entra group | `Azure Kubernetes Service Cluster User Role` | Generated AKS cluster | Fetch user kubeconfig |
| Developers Entra group | `Azure Kubernetes Service RBAC Writer` | Generated AKS cluster | Namespace workload access |

All data-plane access uses service-specific roles. Management-plane roles are limited to the
network resource group, managed identity, or AKS cluster as appropriate.

---

## 10. Deployment and Rollback

1. Bootstrap state locally from the reviewed saved plan.
2. Configure state data-plane RBAC and the generated storage account variable.
3. Push this branch to the fork and run the workflow with `plan`.
4. Review all five stack plans, then manually dispatch `apply`.
5. If deployment fails, fix the failing stack and rerun; already-applied stacks remain represented
   by separate remote-state keys.
6. To remove the POC, dispatch `destroy` with `destroy-dev`. Stacks are destroyed in reverse order.
7. Preserve `00-bootstrap` and its state for audit/recovery unless a separate destructive action is
   explicitly approved.

---

## 11. Files

| File | Purpose | Status |
|------|---------|--------|
| `.azure/deployment-plan.md` | Deployment source of truth | Complete |
| `.github/workflows/deploy.yml` | Guarded Terraform CD workflow | Generated |
| `config/dev/00-bootstrap.tfvars` | State bootstrap configuration | Generated |
| `config/dev/05-entra-groups.tfvars` | Entra group membership | Configured |
| `config/dev/10-network.tfvars` | Spoke and hub integration | Configured |
| `config/dev/20-firewall-rules.tfvars` | AKS egress policy | Configured |
| `config/dev/30-supporting-services.tfvars` | Private platform services | Configured |
| `config/dev/40-aks.tfvars` | AKS settings | Pending POC sizing update |

---

## 12. Next Step

Obtain user approval, apply the planned POC sizing changes, and hand off to Azure validation.
