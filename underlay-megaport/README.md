# Underlay: provider0 (Megaport) → AWS Direct Connect

Standalone Terraform root that provisions the physical underlay between AL's network and the Aviatrix PoC architecture via Megaport and AWS Direct Connect.

**Isolated by design.** This directory has no Terraform dependency on the main architecture. It takes `aws_dx_gateway_id` as an input variable. To swap for a different underlay provider, delete this folder and create `underlay-<provider>/` with the same interface.

---

## What it deploys

```
AL on-prem router
      │
      │ cross-connect (ordered via Megaport portal or staff)
      ▼
Megaport Port  (Equinix LD5, 1 Gbps)
      │
      │ VXC 50 Mbps  [megaport_vxc — connect_type=AWSHC]
      ▼
AWS DX Hosted Connection  (eu-west-1)
      │
      │ Hosted Private VIF  [aws_dx_hosted_private_virtual_interface_accepter]
      ▼
AWS DX Gateway (08af4365-b80d-42d3-8fcf-f775401d3731)
      │
      ▼
VGW → Aviatrix Transit VPC (10.10/23)
      │
      ▼
Aviatrix spokes: 10.20/23, 10.21/23
```

BGP session: AL router ↔ AWS, advertising prefixes in both directions.

---

## Prerequisites

### 1. Main architecture deployed

The root module must be applied first. This module needs its `aws_dx_gateway_id` output:

```bash
terraform -chdir=.. output dx_gateway_id
```

### 2. Megaport account

AL needs an active Megaport account with billing configured and a physical presence (or colocation agreement) at a Megaport-connected facility near eu-west-1. Equinix Dublin DB3 is the recommended location — same city as AWS eu-west-1, minimises latency. Equinix London LD5 is the fallback. Exact Megaport location names: `Equinix Dublin DB3` (ID 894), `Equinix London LD5` (ID 90).

### 3. Megaport M2M credentials

The Terraform provider requires **M2M credentials** (OAuth2 client_credentials flow), not legacy API keys.

**How to get them:**

1. Log into [portal.megaport.com](https://portal.megaport.com)
2. Top-right → account menu → **My Account**
3. **Company Settings** tab → **M2M Credentials** section
4. Click **Generate M2M Credentials**
5. Copy **Client ID** → `provider0_access_key`
6. Copy **Client Secret** → `provider0_secret_key` (shown once — save immediately)

> **Note:** The "API Keys" section in My Account is the legacy v2 API — it will not work with Terraform provider 1.x. You must use M2M Credentials specifically.

---

## Step-by-step deployment

### Step 1 — Prepare tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Fill in at minimum:
- `provider0_access_key` / `provider0_secret_key` — from Megaport M2M credentials
- `bgp_auth_key` — any shared secret string, agree with AL network team

Everything else has working defaults for this PoC.

### Step 2 — Init and plan

```bash
terraform init
terraform plan
```

The plan shows 3 resources: `megaport_port`, `megaport_vxc`, `aws_dx_hosted_private_virtual_interface_accepter`.

### Step 3 — Apply

```bash
terraform apply
```

This provisions the Megaport Port and VXC. The VXC creation triggers Megaport to request a Hosted Connection in AWS on AL's behalf. The `aws_dx_hosted_private_virtual_interface_accepter` resource accepts the Hosted Private VIF automatically.

> **Timing:** Megaport VXC provisioning typically takes 2–5 minutes. The VIF acceptance depends on Megaport completing provisioning first. If apply times out, re-run — it is idempotent.

### Step 4 — Verify DX connection state

```bash
# From apply outputs:
terraform output bgp_status_check | bash
```

Expected progression:
| State | Meaning |
|---|---|
| `pending` | AWS waiting for Megaport provisioning |
| `available` | VIF ready, BGP can establish |
| `down` | VIF up, BGP not yet established |
| `verifying` | BGP establishing |

### Step 5 — Configure BGP on AL's router

AL's on-prem router needs a BGP session toward the AWS peer IP:

- **AWS peer IP**: visible in `aws directconnect describe-virtual-interfaces` → `amazonAddress`
- **AL router IP**: `customerAddress` from same output
- **AWS BGP ASN**: `64512` (Amazon side, hard-coded)
- **AL BGP ASN**: `65000` (default, set via `bgp_asn_customer` variable)
- **Auth key**: value of `bgp_auth_key` from tfvars

Once BGP is up, VIF state transitions to `available` and AWS starts advertising VPC CIDRs (`10.10/23`, `10.20/23`, `10.21/23`) toward AL's network.

### Step 6 — Verify reachability

From AL's on-prem network, test connectivity to spoke VMs:

```bash
# AWS Spoke 1 (private IP)
ping 10.20.0.x

# AWS Spoke 2 (private IP)
ping 10.21.0.x

# HTTP (nginx location page)
curl http://10.20.0.x
curl http://10.21.0.x
```

---

## Teardown

```bash
terraform destroy
```

Destroys VIF accepter, VXC, and Port. The DX Gateway and VGW in the main architecture are unaffected — destroy the root module separately if needed.

---

## Replacing with a different underlay provider

This module exposes a single interface to the main architecture:

| Input | Description |
|---|---|
| `aws_dx_gateway_id` | DX Gateway to terminate the VIF on |

To replace with Orange SDN or another provider:

1. `terraform destroy` this module
2. Create `underlay-orange/` (or equivalent) with the same `aws_dx_gateway_id` input variable
3. Implement the equivalent Port → VXC → VIF acceptance flow using the new provider's Terraform provider

The main architecture (`dx_gateway.tf`, VGW association) requires zero changes.

---

## Variables reference

| Variable | Default | Description |
|---|---|---|
| `provider0_access_key` | — | Megaport M2M Client ID |
| `provider0_secret_key` | — | Megaport M2M Client Secret |
| `provider0_location` | `Equinix Dublin DB3` | Megaport datacenter name (exact string) |
| `aws_dx_gateway_id` | — | DX Gateway ID from root module |
| `aws_account_id` | `211098808963` | AWS account hosting the DX Gateway |
| `aws_region` | `eu-west-1` | AWS region |
| `port_speed` | `1000` | Megaport port speed (Mbps) |
| `vxc_bandwidth` | `50` | VXC bandwidth (Mbps) |
| `vlan` | `100` | VLAN for VXC and VIF |
| `bgp_asn_customer` | `65000` | AL-side BGP ASN |
| `bgp_auth_key` | `""` | BGP MD5 auth key |
| `port_term` | `1` | Contract term in months |
