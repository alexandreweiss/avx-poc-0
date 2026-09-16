# Optional: AWS Direct Connect Gateway
# Set var.deploy_dx_gateway = true when DX circuit is available.
# Creates a VGW attached to the Aviatrix transit VPC and associates it with the DXGW.

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
}
