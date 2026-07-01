# Aviatrix Multicloud PoC — AWS Dublin + GCP Frankfurt

Terraform proof-of-concept for AL, demonstrating Aviatrix in a multicloud environment: two transit gateways (AWS eu-west-1 and GCP europe-west3) connected over Orange's private underlay, three spoke gateways with workload VMs, DCF east-west segmentation, and ready-to-activate stubs for AWS Direct Connect and GCP Partner Interconnect.

---

## Business Context

AL is evaluating Aviatrix as the multicloud networking layer for workloads split across AWS and GCP, with Orange's private network infrastructure as the underlay between the two clouds.

This PoC demonstrates four capabilities in a single deployable lab:

**Automation** — The entire multicloud network (two cloud providers, two transit gateways, three spokes, peering, DCF policies, test VMs) is deployed from a single `terraform apply`. Infrastructure is version-controlled, repeatable, and self-documenting.

**Visibility** — Aviatrix CoPilot provides a unified topology view spanning both AWS and GCP, flow logs from every gateway, latency metrics between clouds, and a single pane of glass for operations.

**Security** — Distributed Cloud Firewall (DCF) enforces east-west segmentation between spoke workloads with smart group tagging (no IP management), default deny, and per-flow logging. All policies are defined in code alongside the infrastructure.

**Encryption** — All data-plane traffic traversing the Aviatrix overlay is encrypted end-to-end with AES-256 / High-Performance Encryption (HPE). The transit peering between AWS Dublin and GCP Frankfurt is fully encrypted regardless of the underlay.

**Private underlay ready** — The AWS Direct Connect Gateway and GCP Partner Interconnect stubs are included in this repo and can be activated with a single variable flip (`deploy_dx_gateway = true`, `deploy_gcp_interconnect = true`) once Orange's circuits toward AL are provisioned. The overlay and DCF policies require no changes.

---

## Architecture

```
                Orange Private Underlay
     ┌──────────────────────────────────────────┐
     │                                          │
     │   AWS eu-west-1 (Dublin)                 │   GCP europe-west3 (Frankfurt)
     │  ┌─────────────────────────┐             │  ┌─────────────────────────┐
     │  │  transit-aws-dublin     │◄────────────┼─►│  transit-gcp-paris      │
     │  │  10.10.0.0/23           │  encrypted  │  │  10.30.0.0/23           │
     │  │  c5.xlarge              │  peering    │  │  n1-standard-2          │
     │  │                         │             │  │                         │
     │  │  spoke-aws1  10.20/23   │             │  │  spoke-gcp   10.31/23   │
     │  │  └─ EC2 Ubuntu + nginx  │             │  │  └─ GCE Ubuntu + nginx  │
     │  │                         │             │  └─────────────────────────┘
     │  │  spoke-aws2  10.21/23   │             │
     │  │  └─ EC2 Ubuntu + nginx  │             │
     │  │                         │             │
     │  │  [AWS DX Gateway]       │             │  [GCP Partner Interconnect]
     │  │  (optional stub)        │◄────────────┼─►(optional stub)
     │  └─────────────────────────┘             │
     └──────────────────────────────────────────┘

DCF smart groups: spoke-aws1-vms · spoke-aws2-vms · spoke-gcp-vms
DCF policy:       east-west PERMIT (all spokes ↔ all spokes) · default DENY
```

### Two Terraform roots

| Root | Purpose |
|---|---|
| `controlplane/` | Deploy Aviatrix Controller + CoPilot on AWS (one-time, skip if a Controller is already running) |
| `.` (repo root) | Deploy the multicloud network against an existing Controller |

---

## Prerequisites

### AL tenant accounts

Two cloud accounts from AL's tenant are required before deploying anything.

#### AWS account (`eu-west-1`)

IAM credentials (access key + secret) with permissions to create VPCs, EC2 instances, key pairs, security groups, and EIPs. The account must have enough quota for the resources below — check limits in **Service Quotas → EC2** before applying.

**Aviatrix IAM roles** — Aviatrix requires two IAM roles (`aviatrix-role-ec2` and `aviatrix-role-app`) in the AWS account to allow the Controller to manage resources. Two options:

- **Automatic** — if `create_iam_roles = true` in `controlplane/terraform.tfvars` (default), the controlplane module creates the roles automatically during Controller deployment.
- **Manual** — if the roles already exist or need to be pre-created by AL's cloud team, follow the Aviatrix documentation: [IAM role setup](https://docs.aviatrix.com/docs/enterprise/9.0/reference/general/iam-role#notes-for-the-custom-iam-role-name-feature). Set `create_iam_roles = false` in `controlplane/terraform.tfvars` to skip automatic creation.

| Resource | Consumed | Default limit | Notes |
|---|---|---|---|
| Elastic IPs (EIPs) | **3** | 5 per region | 1× transit gateway + 2× spoke gateways. If the Controller and CoPilot also run in this account, they consume 2 more EIPs — total 5, right at the default limit. Request a quota increase to 10 if needed. |
| VPCs | **4** | 5 per region | 1× transit VPC + 2× spoke VPCs + 1× controlplane VPC (if Controller deployed here). Request increase if other VPCs already exist. |
| EC2 instances (running) | **5** | varies | 1× transit gateway (`c5.xlarge`) + 2× spoke gateways (`t3.small`) + 2× spoke VMs (`t3.micro`). Controlplane adds 2 more if deployed here. |
| Internet Gateways | **4** | 5 per region | 1 per VPC. Same caveat as VPCs. |
| Security Groups | ~10 | 2500 | No concern in practice. |

> **EIP limit is the most common deployment blocker.** Run `aws ec2 describe-addresses --region eu-west-1` to count currently allocated EIPs before applying.

#### GCP project (`europe-west3`)

A GCP project in AL's organization with the **Compute Engine API** enabled.

**GCP service account** — Aviatrix requires a dedicated GCP service account with specific IAM roles to manage resources in the project. Two options:

- **Recommended (restricted)** — follow the Aviatrix documentation to create a service account with least-privilege access: [GCP account onboarding with restricted access](https://docs.aviatrix.com/docs/enterprise/9.0/guides/platform-administration/gcp-account-onboarding#create-a-service-account-with-restricted-access). Download the JSON key and set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json` before running Terraform.
- **Broad access** — grant `Compute Admin` and `Service Account User` roles. Faster for a PoC but not recommended for production accounts.

The service account must then be onboarded into the Aviatrix Controller (Controller → Onboarding → GCP) using the JSON key before running `terraform apply`.

| Resource | Consumed | Default limit | Notes |
|---|---|---|---|
| CPUs (N1, europe-west3) | **6** | 24 | 1× transit gateway (`n1-standard-2` = 2 vCPU) + 1× spoke gateway (`n1-standard-2` = 2 vCPU) + 1× spoke VM (`e2-micro` = 0.25 vCPU, rounds up). Well within default quota. |
| VPC networks | **2** | 15 | 1× transit VPC + 1× spoke VPC. |
| Static external IPs | **2** | 8 | 1 per Aviatrix gateway. |
| Firewall rules | ~8 | 200 | Aviatrix creates `avx-*` rules automatically per VPC. |

Both accounts must be onboarded into the Aviatrix Controller before running `terraform apply`.

---

### Toolchain

```bash
terraform version   # >= 1.3.0
aws --version
gcloud --version
```

Install links: [Terraform](https://developer.hashicorp.com/terraform/install) · [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) · [gcloud SDK](https://cloud.google.com/sdk/docs/install)

### AWS credentials

```bash
aws sts get-caller-identity
```

Must succeed for the account hosting the PoC gateways.

### GCP credentials

```bash
gcloud auth application-default login
gcloud config set project <PROJECT_ID>
gcloud config get project   # confirm
```

### Aviatrix Controller

Either deploy one via `controlplane/` (see [Deploy the Controller](#deploy-the-controller-optional)) or point at an existing Controller. You need:

- Controller IP or hostname
- Admin password
- Name of the AWS account onboarded in the Controller (Controller > Accounts > AWS)
- Name of the GCP account onboarded in the Controller (Controller > Accounts > GCP)

---

## Quick Start

### 1. Clone and configure

```bash
git clone <this-repo>
cd avx-poc-0
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — minimum required:

```hcl
aviatrix_controller_ip = "<controller-ip-or-hostname>"
aviatrix_password      = "<admin-password>"
aws_account_name       = "<aws-account-name-in-controller>"
gcp_account_name       = "<gcp-account-name-in-controller>"
gcp_project_id         = "<gcp-project-id>"
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes approximately 20–30 minutes. Gateway provisioning is the bottleneck.

### 3. Verify

Run the full automated test suite:

```bash
./tests.sh
```

Or check individual nginx pages:

```bash
terraform output nginx_url_aws1
terraform output nginx_url_aws2
terraform output nginx_url_gcp
```

Each page confirms the VM's cloud and region, and SSH commands are ready in the outputs.

---

## Variables Reference

### Required

| Variable | Description |
|---|---|
| `aviatrix_controller_ip` | Controller hostname or IP |
| `aviatrix_password` | Controller admin password (sensitive) |
| `aws_account_name` | Aviatrix-onboarded AWS account name |
| `gcp_account_name` | Aviatrix-onboarded GCP account name |
| `gcp_project_id` | GCP project ID (not display name) |

### Optional — network

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `eu-west-1` | AWS region (Dublin) |
| `gcp_region` | `europe-west3` | GCP region (Frankfurt) |
| `transit_aws_cidr` | `10.10.0.0/23` | AWS transit VPC CIDR |
| `transit_gcp_cidr` | `10.30.0.0/23` | GCP transit VPC CIDR |
| `spoke_aws1_cidr` | `10.20.0.0/23` | AWS spoke 1 VPC CIDR |
| `spoke_aws2_cidr` | `10.21.0.0/23` | AWS spoke 2 VPC CIDR |
| `spoke_gcp_cidr` | `10.31.0.0/23` | GCP spoke VPC CIDR |

### Optional — gateway sizing

| Variable | Default | Description |
|---|---|---|
| `transit_aws_gw_size` | `c5.xlarge` | AWS transit gateway instance size |
| `transit_gcp_gw_size` | `n1-standard-2` | GCP transit gateway instance size |
| `spoke_aws_gw_size` | `t3.small` | AWS spoke gateway instance size |
| `spoke_gcp_gw_size` | `n1-standard-2` | GCP spoke gateway instance size |
| `spoke_vm_instance_type` | `t3.micro` | EC2 instance type for spoke VMs |
| `spoke_gcp_vm_type` | `e2-micro` | GCP instance type for spoke VM |

### Optional — private underlay stubs

| Variable | Default | Description |
|---|---|---|
| `deploy_dx_gateway` | `false` | Deploy AWS Direct Connect Gateway attached to AWS transit |
| `dx_gateway_asn` | `64512` | BGP ASN for the DX Gateway |
| `dx_gateway_name` | `poc-dx-gateway` | DX Gateway name |
| `deploy_gcp_interconnect` | `false` | Deploy GCP Partner Interconnect VLAN attachments |
| `gcp_interconnect_router_asn` | `65000` | BGP ASN for the GCP Cloud Router |
| `gcp_interconnect_bandwidth` | `BPS_1G` | Bandwidth for VLAN attachment |
| `gcp_interconnect_pairing_key` | `""` | Pairing key from partner (leave empty on first apply) |

---

## Outputs

| Output | Description |
|---|---|
| `ssh_connect_aws1` | Ready SSH command for AWS spoke 1 VM |
| `ssh_connect_aws2` | Ready SSH command for AWS spoke 2 VM |
| `ssh_connect_gcp` | Ready SSH command for GCP spoke VM |
| `nginx_url_aws1` | HTTP URL for AWS spoke 1 nginx page |
| `nginx_url_aws2` | HTTP URL for AWS spoke 2 nginx page |
| `nginx_url_gcp` | HTTP URL for GCP spoke nginx page |
| `ssh_private_key_path` | Path to generated `spoke-vms.pem` (chmod 600, gitignored) |
| `dx_gateway_id` | AWS Direct Connect Gateway ID (if deployed) |
| `gcp_interconnect_pairing_key` | GCP Partner Interconnect pairing key to give to Orange (if deployed) |

---

## DCF Policy Detail

Distributed Cloud Firewall is enabled at the controller level and enforced at each spoke gateway. Smart groups use VM tags (AWS) and CIDR (GCP) to identify workloads — no manual IP management.

| Priority | Rule | Action |
|---|---|---|
| 100–105 | spoke-aws1 ↔ spoke-aws2 ↔ spoke-gcp (all pairs) | PERMIT ANY |
| 200–201 | Anywhere → Public Internet via AllWeb (TCP 80, 443) | PERMIT |
| 65000 | Anywhere → Anywhere | DENY (logged) |

All rules log matched flows. Flow logs are visible in CoPilot > Security > Distributed Cloud Firewall > Monitor.

---

## Activating the Orange Underlay

When Orange's circuits are available, activate the private underlay stubs without touching the overlay or DCF configuration:

### AWS Direct Connect

```hcl
# terraform.tfvars
deploy_dx_gateway = true
dx_gateway_asn    = 64512       # optional — match Orange's BGP config
dx_gateway_name   = "poc-dx-gw" # optional
```

This creates an `aws_dx_gateway` with a Virtual Gateway (VGW) association on the AWS transit VPC. Order the DX Connection and Private VIF separately via AWS Console or through Orange as the connectivity partner.

### GCP Partner Interconnect

Two-step process (pairing key must be exchanged with Orange):

**Step 1** — Create the VLAN attachment to obtain the pairing key:

```hcl
# terraform.tfvars
deploy_gcp_interconnect      = true
gcp_interconnect_pairing_key = ""   # leave empty
```

```bash
terraform apply
terraform output gcp_interconnect_pairing_key
```

**Step 2** — Give the pairing key to Orange, then complete the attachment:

```hcl
# terraform.tfvars
gcp_interconnect_pairing_key = "<key-from-step-1>"
```

```bash
terraform apply
```

The attachment transitions from `PENDING_CUSTOMER` to `ACTIVE` once Orange provisions their side of the circuit.

---

## Deploy the Controller (optional)

Skip this section if an Aviatrix Controller is already running. Use the existing Controller's IP and password directly in `terraform.tfvars`.

If you need to deploy a fresh Controller:

```bash
cd controlplane
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — see below for required values
terraform init
terraform apply
```

Required values for `controlplane/terraform.tfvars`:

| Variable | Description |
|---|---|
| `controller_admin_email` | Admin email for the Controller |
| `controller_admin_password` | Admin password (sensitive) |
| `customer_id` | Aviatrix license ID (`xxxxxxx-abu-xxxxxxxxx`) |
| `access_account_name` | Name to give the AWS account inside the Controller |
| `account_email` | Email for the AWS access account |
| `incoming_ssl_cidrs` | Your public IP in CIDR form (`curl -s https://checkip.amazonaws.com` → append `/32`) |

After apply, note the outputs:
- `controller_public_ip` → use as `aviatrix_controller_ip` in root `terraform.tfvars`
- `access_account_name` → use as `aws_account_name`
- `controller_url` / `copilot_url` → browser access

Wait ~5 minutes for Controller bootstrap to complete before running the root module.

---

## Teardown

Destroy the root module first, then the Controller if it was deployed here:

```bash
# From repo root
terraform destroy

# Only if you want to tear down the Controller too
cd controlplane
terraform destroy
```

Remove the generated SSH key:

```bash
rm spoke-vms.pem
```

---

## Cost Estimate (CSP only)

> **Aviatrix licensing:** Aviatrix offers a 30-day free trial — license costs are waived for the trial period. Only CSP infrastructure costs apply during a PoC.

These are **cloud provider infrastructure costs only**. All figures are approximate, based on on-demand pricing in `eu-west-1` (AWS) and `europe-west3` (GCP) as of mid-2025. Costs scale linearly with uptime.

### AWS (`eu-west-1`)

| Resource | Type | $/hr | 8 hr/day est. |
|---|---|---|---|
| Transit gateway EC2 | `c5.xlarge` | ~$0.192 | ~$1.54 |
| Spoke gateway 1 EC2 | `t3.small` | ~$0.023 | ~$0.18 |
| Spoke gateway 2 EC2 | `t3.small` | ~$0.023 | ~$0.18 |
| Spoke VM 1 EC2 | `t3.micro` | ~$0.012 | ~$0.10 |
| Spoke VM 2 EC2 | `t3.micro` | ~$0.012 | ~$0.10 |
| EIPs (3 × idle rate) | — | ~$0.011 | ~$0.09 |
| **AWS subtotal** | | **~$0.27/hr** | **~$2.19/day** |

### GCP (`europe-west3`)

| Resource | Type | $/hr | 8 hr/day est. |
|---|---|---|---|
| Transit gateway VM | `n1-standard-2` | ~$0.112 | ~$0.90 |
| Spoke gateway VM | `n1-standard-2` | ~$0.112 | ~$0.90 |
| Spoke VM | `e2-micro` | ~$0.008 | ~$0.06 |
| Static external IPs (2) | — | ~$0.010 | ~$0.08 |
| **GCP subtotal** | | **~$0.24/hr** | **~$1.94/day** |

### Summary

| Scenario | AWS | GCP | **Total** |
|---|---|---|---|
| Active 8 hrs/day | ~$2.19 | ~$1.94 | **~$4.13/day** |
| Active 24 hrs/day | ~$6.58 | ~$5.81 | **~$12.39/day** |
| Full week (8 hrs/day) | ~$15.30 | ~$13.55 | **~$28.85/week** |

### Optional: Private Underlay (Orange circuits — 50 Mbps)

These costs apply when `deploy_dx_gateway = true` and/or `deploy_gcp_interconnect = true`. Billed by the CSP regardless of traffic volume — circuit pricing is always-on.

#### AWS Direct Connect (50 Mbps, eu-west-1)

AWS does not offer a native 50 Mbps DX port. The smallest available port is **100 Mbps hosted connection** (via a DX partner such as Orange). Dedicated ports start at 1 Gbps.

| Component | Billing model | Monthly cost (est.) |
|---|---|---|
| Hosted connection (100 Mbps via partner) | Partner-priced — not billed by AWS directly. Orange charges AL separately. | Partner rate |
| AWS DX Gateway | No charge | $0 |
| AWS Virtual Private Gateway (VGW) | No charge | $0 |
| DX data transfer out (AWS → on-prem) | $0.02/GB (eu-west-1, private VIF) | Usage-based |
| **AWS CSP fixed cost** | | **$0** (partner circuit billed by Orange) |

> Orange orders the hosted connection on AL's behalf. AWS bills only for data transfer over the VIF — not the port itself on a hosted connection.

#### GCP Partner Interconnect (50 Mbps, europe-west3)

Partner Interconnect supports capacities starting at 50 Mbps (VLAN attachment). The circuit is ordered through a partner (Orange).

| Component | Billing model | Monthly cost (est.) |
|---|---|---|
| VLAN attachment — 50 Mbps | $0.05/hr (GCP charges for the attachment itself) | **~$36/month** |
| Partner capacity (50 Mbps) | Partner-priced — Orange charges AL separately | Partner rate |
| GCP Cloud Router | $0.01/hr per VPN tunnel equivalent | ~$7/month |
| Egress over interconnect (GCP → on-prem) | $0.02/GB | Usage-based |
| **GCP CSP fixed cost** | | **~$43/month** |

### Summary with private underlay

| Scenario | AWS+GCP compute | DX (AWS CSP) | Partner Interconnect (GCP CSP) | **Total CSP/month** |
|---|---|---|---|---|
| PoC only (internet overlay) | ~$372 | — | — | **~$372** |
| + AWS DX stub activated | ~$372 | $0 | — | **~$372** (Orange bills separately) |
| + GCP Interconnect stub activated | ~$372 | — | ~$43 | **~$415** |
| Both underlay stubs active | ~$372 | $0 | ~$43 | **~$415** |

> Compute estimate assumes 24/7 operation for 30 days. Orange's circuit charges (DX hosted connection + Partner Interconnect capacity) are not included — these are negotiated directly between Orange and AL.

> **Tip — stop instead of destroy:** Aviatrix gateways are EC2/GCE instances. Stopping them overnight via the Controller halts compute billing while preserving configuration. EIPs and static IPs continue to accrue a small idle charge (~$0.005/hr per IP) unless released. GCP VLAN attachment billing continues even when gateways are stopped.

> **Data transfer:** Cross-cloud egress (AWS → internet toward GCP) is billed by AWS at ~$0.09/GB. For a PoC with light test traffic this is negligible (<$1 total). With private underlay active, egress over the circuit drops to ~$0.02/GB.

---

## Tests

`tests.sh` runs an automated connectivity and policy validation suite against the deployed infrastructure. No arguments needed — just run from the repo root after `terraform apply`.

```bash
./tests.sh
```

### Test checklist

| # | Pass | Test | What it proves | Comments |
|---|:----:|---|---|---|
| 1 | [ ] | Public nginx — AWS Spoke 1 | Internet reachability, VM up | |
| 2 | [ ] | Public nginx — AWS Spoke 2 | Internet reachability, VM up | |
| 3 | [ ] | Public nginx — GCP Spoke | Internet reachability, VM up | |
| 4 | [ ] | AWS Spoke 1 → AWS Spoke 2 (private IP) | East-west same cloud | |
| 5 | [ ] | AWS Spoke 2 → AWS Spoke 1 (private IP) | Bidirectional same cloud | |
| 6 | [ ] | AWS → GCP (private IP) | Cross-cloud via transit peering | |
| 7 | [ ] | GCP → AWS (private IP) | Bidirectional cross-cloud | |
| 8 | [ ] | Cross-cloud ICMP RTT | Latency baseline (~22 ms Dublin ↔ Frankfurt) | |
| 9 | [ ] | HTTP egress from spoke | DCF AllWeb egress PERMIT active | |
| 10 | [ ] | Controller API login | Aviatrix control plane reachable | |
| 11 | [ ] | Traceroute AWS → GCP | Gateway hop visible, tunnel hops no-reply (expected) | |
| 12 | [ ] | DCF default DENY | Direct spoke-to-spoke without policy blocked | |

Expected: **12 passed, 0 failed**.

No-reply hops in traceroute are intentional — traffic is encapsulated in the Aviatrix encrypted tunnel after the first gateway hop.

---

## Known Gotchas

- `aviatrix_distributed_firewalling_config` is controller-global — only one instance per controller. If DCF is already enabled on this controller by another workspace, import the resource before applying: `terraform import aviatrix_distributed_firewalling_config.this distributed_firewalling_config`
- GCP VPC subnets: `subnets[0]` is the gateway subnet; workload VMs use `subnets[1]`
- GCP `google_compute_interconnect_attachment` with `type = "PARTNER"` and an empty `pairing_key` is valid on first create — the attachment enters `PENDING_CUSTOMER` state awaiting the partner
- `mc-transit` module 9.0.0 requires Aviatrix provider `>= 9.0.0`
- After `controlplane/` apply, wait ~5 minutes for Controller bootstrap before running the root module
