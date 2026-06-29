# provider0 underlay for AWS Direct Connect (Step 1 + Step 2)
#
# Deploys:
#   1. provider0 Port at a DX-connected facility near eu-west-1
#   2. VXC from that port to AWS Direct Connect (Hosted Connection)
#   3. Accepts the Hosted Connection in AWS
#   4. Creates a Private VIF on the connection, pointing at the DX Gateway
#
# Prerequisites (from root module):
#   - aws_dx_gateway already exists (var.aws_dx_gateway_id)
#   - VGW already associated with that DX Gateway
#
# To replace with another underlay provider: delete this directory and create
# underlay-<provider>/ with the same var.aws_dx_gateway_id input.

# --- Discover provider0 location ---

data "megaport_location" "this" {
  name    = var.provider0_location
  has_mcr = false
}

# --- provider0 Port (AL's on-ramp) ---

resource "megaport_port" "this" {
  product_name           = var.port_name
  port_speed             = var.port_speed
  location_id            = data.megaport_location.this.id
  contract_term_months   = var.port_term
  marketplace_visibility = false
}

# --- VXC to AWS Direct Connect ---
# Creates a Hosted Connection that will appear in the AWS account for acceptance.

resource "megaport_vxc" "aws_dx" {
  product_name         = var.vxc_name
  rate_limit           = var.vxc_bandwidth
  contract_term_months = var.port_term

  a_end = {
    requested_product_uid = megaport_port.this.product_uid
    ordered_vlan          = var.vlan
  }

  b_end = {
    requested_product_uid = data.megaport_location.this.id
  }

  b_end_partner_config = {
    partner = "aws"
    aws_config = {
      name          = var.vxc_name
      account_id    = var.aws_account_id
      amazon_asn    = 64512
      customer_asn  = var.bgp_asn_customer
      auth_key      = var.bgp_auth_key != "" ? var.bgp_auth_key : null
      connect_type  = "HOSTED"
      type          = "private"
      prefixes      = ""
    }
  }
}

# --- Accept the Hosted Connection in AWS ---
# provider0 provisions it; AWS puts it in PENDING state until accepted.

resource "aws_dx_hosted_connection_accepter" "this" {
  connection_id = megaport_vxc.aws_dx.b_end.product_uid

  depends_on = [megaport_vxc.aws_dx]
}

# --- Private VIF on the accepted connection ---

resource "aws_dx_private_virtual_interface" "this" {
  connection_id    = megaport_vxc.aws_dx.b_end.product_uid
  name             = var.vif_name
  vlan             = var.vlan
  address_family   = "ipv4"
  bgp_asn          = var.bgp_asn_customer
  bgp_auth_key     = var.bgp_auth_key != "" ? var.bgp_auth_key : null
  dx_gateway_id    = var.aws_dx_gateway_id

  depends_on = [aws_dx_hosted_connection_accepter.this]
}
