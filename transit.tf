# --- AWS Transit (Dublin, eu-west-1) ---

module "transit_aws" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "9.0.0"

  cloud         = "aws"
  region        = var.aws_region
  account       = var.aws_account_name
  cidr          = var.transit_aws_cidr
  name          = "transit-aws-dublin"
  instance_size = var.transit_aws_gw_size
  ha_gw         = false

  connected_transit      = true
  enable_transit_firenet = false
}

# --- GCP Transit (Frankfurt, europe-west3) ---

module "transit_gcp" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "9.0.0"

  cloud   = "gcp"
  region  = var.gcp_region
  account       = var.gcp_account_name
  cidr          = var.transit_gcp_cidr
  name          = "transit-gcp-paris"
  instance_size = var.transit_gcp_gw_size
  ha_gw = false

  connected_transit = true
}

# --- AWS ↔ GCP Transit Peering ---

resource "aviatrix_transit_gateway_peering" "aws_gcp" {
  transit_gateway_name1 = module.transit_aws.transit_gateway.gw_name
  transit_gateway_name2 = module.transit_gcp.transit_gateway.gw_name
}

# --- DCF: enable distributed firewalling on the controller ---

resource "aviatrix_distributed_firewalling_config" "this" {
  enable_distributed_firewalling = true
}
