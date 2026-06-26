# --- AWS Spoke 1 (Dublin) ---

resource "aviatrix_vpc" "spoke_aws1" {
  cloud_type           = 1
  account_name         = var.aws_account_name
  region               = var.aws_region
  name                 = "spoke-aws1-vpc"
  cidr                 = var.spoke_aws1_cidr
  aviatrix_transit_vpc = false
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "aws1" {
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "spoke-aws1-gw"
  vpc_id       = aviatrix_vpc.spoke_aws1.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.spoke_aws_gw_size
  subnet       = aviatrix_vpc.spoke_aws1.public_subnets[0].cidr
}

resource "aviatrix_spoke_transit_attachment" "aws1" {
  spoke_gw_name   = aviatrix_spoke_gateway.aws1.gw_name
  transit_gw_name = module.transit_aws.transit_gateway.gw_name
}

# --- AWS Spoke 2 (Dublin) ---

resource "aviatrix_vpc" "spoke_aws2" {
  cloud_type           = 1
  account_name         = var.aws_account_name
  region               = var.aws_region
  name                 = "spoke-aws2-vpc"
  cidr                 = var.spoke_aws2_cidr
  aviatrix_transit_vpc = false
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "aws2" {
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "spoke-aws2-gw"
  vpc_id       = aviatrix_vpc.spoke_aws2.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.spoke_aws_gw_size
  subnet       = aviatrix_vpc.spoke_aws2.public_subnets[0].cidr
}

resource "aviatrix_spoke_transit_attachment" "aws2" {
  spoke_gw_name   = aviatrix_spoke_gateway.aws2.gw_name
  transit_gw_name = module.transit_aws.transit_gateway.gw_name
}

# --- GCP Spoke (Frankfurt) ---

resource "aviatrix_vpc" "spoke_gcp" {
  cloud_type   = 4
  account_name = var.gcp_account_name
  name         = "spoke-gcp-vpc"

  subnets {
    name   = "spoke-gcp-vpc"
    cidr   = var.spoke_gcp_cidr
    region = var.gcp_region
  }
}

resource "aviatrix_spoke_gateway" "gcp" {
  cloud_type   = 4
  account_name = var.gcp_account_name
  gw_name      = "spoke-gcp-gw"
  vpc_id       = aviatrix_vpc.spoke_gcp.vpc_id
  vpc_reg      = "${var.gcp_region}-b"
  gw_size      = var.spoke_gcp_gw_size
  subnet       = aviatrix_vpc.spoke_gcp.subnets[0].cidr
}

resource "aviatrix_spoke_transit_attachment" "gcp" {
  spoke_gw_name   = aviatrix_spoke_gateway.gcp.gw_name
  transit_gw_name = module.transit_gcp.transit_gateway.gw_name
}
