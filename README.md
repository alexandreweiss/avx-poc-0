# Aviatrix Multicloud PoC — AWS Dublin + GCP Paris

Terraform proof-of-concept for Orange, demonstrating Aviatrix in a multicloud environment: two transit gateways (AWS eu-west-1 and GCP europe-west9) connected over a private underlay, three spoke gateways with workload VMs, DCF east-west segmentation, and ready-to-activate stubs for AWS Direct Connect and GCP Partner Interconnect.

---

## Business Context

Orange is evaluating Aviatrix as the multicloud networking layer for workloads split across AWS and GCP, with Orange's own network infrastructure as the private underlay between the two clouds.

This PoC demonstrates four capabilities in a single deployable lab:

**Automation** — The entire multicloud network (two cloud providers, two transit gateways, three spokes, peering, DCF policies, test VMs) is deployed from a single `terraform apply`. Infrastructure is version-controlled, repeatable, and self-documenting.

**Visibility** — Aviatrix CoPilot provides a unified topology view spanning both AWS and GCP, flow logs from every gateway, latency metrics between clouds, and a single pane of glass for operations.

**Security** — Distributed Cloud Firewall (DCF) enforces east-west segmentation between spoke workloads with smart group tagging (no IP management), default deny, and per-flow logging. All policies are defined in code alongside the infrastructure.

**Encryption** — All data-plane traffic traversing the Aviatrix overlay is encrypted end-to-end with AES-256 / High-Performance Encryption (HPE). The transit peering between AWS Dublin and GCP Paris is fully encrypted regardless of the underlay.

**Private underlay ready** — The AWS Direct Connect Gateway and GCP Partner Interconnect stubs are included in this repo and can be activated with a single variable flip (`deploy_dx_gateway = true`, `deploy_gcp_interconnect = true`) once Orange's circuits are provisioned. The overlay and DCF policies require no changes.

---

## Architecture

```
                Orange Private Underlay
     ┌──────────────────────────────────────────┐
     │                                          │
     │   AWS eu-west-1 (Dublin)                 │   GCP europe-west9 (Paris)
     │  ┌─────────────────────────┐             │  ┌─────────────────────────┐
     │  │  transit-aws-dublin     │◄────────────┼─►│  transit-gcp-paris      │
     │  │  10.10.0.0/23           │  encrypted  │  │  10.30.0.0/23           │
     │  │  c5.xlarge              │  peering    │  │  n1-standard-1          │
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

After `apply` completes, test connectivity between clouds:

```bash
# SSH to AWS spoke 1
$(terraform output -raw ssh_connect_aws1)

# From AWS spoke 1, curl the GCP nginx VM (private IP, cross-cloud)
curl http://10.31.0.x
```

Or open the nginx location pages in a browser:

```bash
terraform output nginx_url_aws1
terraform output nginx_url_aws2
terraform output nginx_url_gcp
```

Each nginx page displays the VM's cloud, region, and private IP — confirming the multicloud overlay is routing correctly.

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
| `gcp_region` | `europe-west9` | GCP region (Paris) |
| `transit_aws_cidr` | `10.10.0.0/23` | AWS transit VPC CIDR |
| `transit_gcp_cidr` | `10.30.0.0/23` | GCP transit VPC CIDR |
| `spoke_aws1_cidr` | `10.20.0.0/23` | AWS spoke 1 VPC CIDR |
| `spoke_aws2_cidr` | `10.21.0.0/23` | AWS spoke 2 VPC CIDR |
| `spoke_gcp_cidr` | `10.31.0.0/23` | GCP spoke VPC CIDR |

### Optional — gateway sizing

| Variable | Default | Description |
|---|---|---|
| `transit_aws_gw_size` | `c5.xlarge` | AWS transit gateway instance size |
| `transit_gcp_gw_size` | `n1-standard-1` | GCP transit gateway instance size |
| `spoke_aws_gw_size` | `t3.small` | AWS spoke gateway instance size |
| `spoke_gcp_gw_size` | `n1-standard-1` | GCP spoke gateway instance size |
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

This creates an `aws_dx_gateway` with a Virtual Gateway (VGW) association on the AWS transit VPC. Order the DX Connection and Private VIF separately via AWS Console or through Orange as the partner.

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

The attachment transitions from `PENDING_CUSTOMER` to `ACTIVE` once Orange provisions their side.

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

## Known Gotchas

- `aviatrix_distributed_firewalling_config` is controller-global — only one instance per controller. If DCF is already enabled on this controller by another workspace, import the resource before applying: `terraform import aviatrix_distributed_firewalling_config.this distributed_firewalling_config`
- GCP VPC subnets: `subnets[0]` is the gateway subnet; workload VMs use `subnets[1]`
- GCP `google_compute_interconnect_attachment` with `type = "PARTNER"` and an empty `pairing_key` is valid on first create — the attachment enters `PENDING_CUSTOMER` state awaiting the partner
- `mc-transit` module 9.0.0 requires Aviatrix provider `>= 9.0.0`
- After `controlplane/` apply, wait ~5 minutes for Controller bootstrap before running the root module
