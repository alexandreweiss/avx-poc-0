# PoC: Aviatrix Multicloud — AWS Dublin + GCP Paris

Terraform PoC deploying two Aviatrix transits (AWS eu-west-1 + GCP europe-west9), three spoke gateways, DCF east-west policies, and optional DX / Partner Interconnect stubs.

Two independent Terraform roots:
- `controlplane/` — deploy the Aviatrix Controller + CoPilot **first**, once, if not already running
- `.` (root) — deploy the multicloud network architecture against an existing Controller

---

## Architecture

```
AWS eu-west-1 (Dublin)               GCP europe-west9 (Paris)
┌──────────────────────────┐         ┌──────────────────────────┐
│  transit-aws-dublin      │◄───────►│  transit-gcp-paris       │
│  (mc-transit 8.2.0)      │  peered │  (mc-transit 8.2.0)      │
│                          │         │                          │
│  spoke-aws1-gw  10.20/23 │         │  spoke-gcp-gw  10.31/23  │
│  └─ EC2 nginx VM         │         │  └─ GCE nginx VM         │
│                          │         └──────────────────────────┘
│  spoke-aws2-gw  10.21/23 │
│  └─ EC2 nginx VM         │
└──────────────────────────┘

CIDRs: transit-aws 10.10/23 · transit-gcp 10.30/23

DCF: east-west PERMIT between all spokes · default DENY
Optional: AWS DX Gateway (deploy_dx_gateway=true)
Optional: GCP Partner Interconnect (deploy_gcp_interconnect=true)
```

---

## Step 0 — Check if Controller already exists

**Always ask the user first:** "Do you already have an Aviatrix Controller running?"

- **Yes** → skip to Step 2 (prerequisites for root module). Ask for controller IP and password.
- **No** → follow Step 1 to deploy one via `controlplane/`.

---

## Step 1 — Deploy the Controller (`controlplane/`)

Only needed if no Controller exists. This is a one-time operation; do not re-run if a Controller is already up.

### What it deploys

Uses module `terraform-aviatrix-modules/aws-controlplane/aviatrix` v1.0.12.
Creates in the target AWS region:
- Controller EC2 (t3.large default) with EIP
- CoPilot EC2 with EIP
- Dedicated VPC (10.0.0.0/24 default)
- Security group restricting port 443 to `incoming_ssl_cidrs`
- Bootstraps Controller (version, admin password, license, onboards the AWS account)

### Prerequisites for controlplane/

Ask the user for these before running anything:

| Item | How to get it |
|---|---|
| AWS credentials active | `aws sts get-caller-identity` must succeed |
| `aws_region` | Default eu-west-1 — confirm with user |
| `controller_admin_email` | User provides |
| `controller_admin_password` | User provides — sensitive, do not log |
| `customer_id` | Aviatrix license ID — format `xxxxxxx-abu-xxxxxxxxx`. User gets it from Aviatrix portal or email. |
| `access_account_name` | Name to give the AWS account inside the Controller (user chooses, e.g. `aws-poc`) |
| `account_email` | Email for the AWS access account |
| `incoming_ssl_cidrs` | User's public IP in CIDR form. Get it: `curl -s https://checkip.amazonaws.com` → append `/32` |

### Deploy controlplane/

```bash
cd controlplane
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with values above
terraform init
terraform plan
terraform apply
```

Note the outputs — you will need them for Step 2:
- `controller_public_ip` → use as `aviatrix_controller_ip` in root module
- `access_account_name` → use as `aws_account_name` in root module
- `controller_url` / `copilot_url` → browser access

After apply, wait ~5 minutes for Controller bootstrap to complete before running the root module.

### Verify Controller is ready

```bash
curl -sk https://<controller_public_ip>/v1/api \
  -d "action=login&username=admin&password=<password>" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('return') else d)"
```

---

## Step 2 — Prerequisites for root module

Verify each item. Ask for missing ones before running any Terraform command.

### Toolchain

```bash
terraform version   # >= 1.3.0
aws --version
gcloud --version
```

If missing: https://developer.hashicorp.com/terraform/install · https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html · https://cloud.google.com/sdk/docs/install

### AWS credentials

```bash
aws sts get-caller-identity
```

Must succeed for the account hosting the PoC gateways. If not: `aws configure` or export `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`.

### GCP credentials

```bash
gcloud auth application-default login
gcloud config set project <PROJECT_ID>
gcloud config get project   # confirm
```

### Values to collect — ASK USER, never assume

| Variable | Source |
|---|---|
| `aviatrix_controller_ip` | Output of controlplane/ or existing controller hostname/IP |
| `aviatrix_password` | Controller admin password |
| `aws_account_name` | Name of AWS account onboarded in Controller (Controller → Accounts → AWS). If deployed via controlplane/, this equals `access_account_name` from that module. |
| `gcp_account_name` | Name of GCP account onboarded in Controller (Controller → Accounts → GCP) |
| `gcp_project_id` | GCP project ID (not name) — `gcloud config get project` |

### terraform.tfvars (root)

```bash
cp terraform.tfvars.example terraform.tfvars
# edit with values above
```

Minimum required:

```hcl
aviatrix_controller_ip = "<ip or hostname>"
aviatrix_password      = "<admin password>"
aws_account_name       = "<name from Controller>"
gcp_account_name       = "<name from Controller>"
gcp_project_id         = "<gcp-project-id>"
```

---

## Step 3 — Deploy root module

```bash
# from repo root (not controlplane/)
terraform init
terraform plan
terraform apply
```

After apply:
- `ssh_connect_aws1/2` — ready SSH commands (key at `spoke-vms.pem`)
- `nginx_url_aws1/2/gcp` — curl/browser to verify nginx location pages
- `ssh_private_key_path` — path to `spoke-vms.pem` (gitignored, chmod 600)

---

## Optional features

### AWS Direct Connect Gateway

```hcl
# terraform.tfvars
deploy_dx_gateway = true
dx_gateway_asn    = 64512        # optional
dx_gateway_name   = "poc-dx-gw"  # optional
```

Creates `aws_dx_gateway` + VGW association on the AWS transit. DX circuit (connection + VIF) ordered separately via AWS Console or partner.

### GCP Partner Interconnect

```hcl
# terraform.tfvars
deploy_gcp_interconnect      = true
gcp_interconnect_pairing_key = ""   # leave empty on first apply to get the pairing key
```

After first apply: `terraform output gcp_interconnect_pairing_key` → give key to partner → set `gcp_interconnect_pairing_key = "<key>"` → re-apply.

---

## Destroy order

Destroy root first, then controlplane (if managed here):

```bash
# root
terraform destroy

# then, if you want to tear down the Controller too:
cd controlplane
terraform destroy
```

Clean up local key:

```bash
rm spoke-vms.pem
```

---

## Known gotchas

- `aviatrix_vpc` GCP: `subnets[0]` is gateway subnet; workload VMs use `subnets[1]`
- `mc-transit` 8.2.0 requires aviatrix provider `~> 8.2`
- `aviatrix_distributed_firewalling_config` is controller-global — only one instance. If DCF already enabled on this controller by another workspace, import it: `terraform import aviatrix_distributed_firewalling_config.this distributed_firewalling_config`
- GCP `google_compute_interconnect_attachment` with `type = "PARTNER"` and empty `pairing_key` is valid on first create (state: PENDING_CUSTOMER)
- After `controlplane/` apply, wait ~5 min for Controller bootstrap before running root module
