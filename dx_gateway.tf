# Optional: AWS Direct Connect Gateway
# Set var.deploy_dx_gateway = true when DX circuit is available.
# The DXGW attaches to the AWS transit VGW via an association.

resource "aws_dx_gateway" "this" {
  count         = var.deploy_dx_gateway ? 1 : 0
  name          = var.dx_gateway_name
  amazon_side_asn = var.dx_gateway_asn
}

# Associate the DX Gateway with the Aviatrix transit's VGW.
# The transit module exposes the VPC's Virtual Private Gateway via the underlying VPC resource.
# We look it up by the VPC ID that mc-transit created.

data "aws_vpn_gateway" "transit_aws" {
  count  = var.deploy_dx_gateway ? 1 : 0

  filter {
    name   = "attachment.vpc-id"
    values = [module.transit_aws.vpc.vpc_id]
  }
}

resource "aws_dx_gateway_association" "transit_aws" {
  count = var.deploy_dx_gateway ? 1 : 0

  dx_gateway_id         = aws_dx_gateway.this[0].id
  associated_gateway_id = data.aws_vpn_gateway.transit_aws[0].id
}
