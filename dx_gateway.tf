# AWS Direct Connect Gateway + VGW association
#
# Orange manages hosted connection + VIF lifecycle using dedicated IAM role.
# Active VIFs: dxvif-fg7gdkba, dxvif-fgrpf172
# Terraform only manages: DXGW + VGW attachment + VGW route propagation on transit public RT.

resource "aws_dx_gateway" "this" {
  count           = var.deploy_dx_gateway ? 1 : 0
  name            = var.dx_gateway_name
  amazon_side_asn = var.dx_gateway_asn
}

resource "aws_vpn_gateway" "transit_aws" {
  count  = var.deploy_dx_gateway ? 1 : 0
  vpc_id = module.transit_aws.vpc.vpc_id

  tags = {
    Name = "poc-transit-aws-vgw"
  }
}

resource "aws_dx_gateway_association" "transit_aws" {
  count = var.deploy_dx_gateway ? 1 : 0

  dx_gateway_id         = aws_dx_gateway.this[0].id
  associated_gateway_id = aws_vpn_gateway.transit_aws[0].id

  allowed_prefixes = [
    var.transit_aws_cidr,
    var.transit_gcp_cidr,
  ]
}

data "aws_route_table" "transit_aws_public" {
  count  = var.deploy_dx_gateway ? 1 : 0
  vpc_id = module.transit_aws.vpc.vpc_id
  filter {
    name   = "tag:Name"
    values = ["${local.transit_aws_name}-Public-rtb"]
  }
}

resource "aws_vpn_gateway_route_propagation" "transit_aws_public" {
  count          = var.deploy_dx_gateway ? 1 : 0
  vpn_gateway_id = aws_vpn_gateway.transit_aws[0].id
  route_table_id = data.aws_route_table.transit_aws_public[0].id
}

