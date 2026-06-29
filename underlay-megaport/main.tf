# provider0 underlay for AWS Direct Connect (Step 1 + Step 2)
#
# Deploys:
#   1. provider0 Port at a DX-connected facility near eu-west-1
#   2. VXC from that port to AWS Direct Connect (Hosted Connection)
#   3. Accepts the Hosted Private VIF in the customer AWS account
#
# Prerequisites (from root module):
#   - aws_dx_gateway already exists (var.aws_dx_gateway_id)
#   - VGW already associated with that DX Gateway
#
# To replace with another underlay provider: delete this directory and create
# underlay-<provider>/ with the same var.aws_dx_gateway_id input.

# --- Discover provider0 location ---

data "megaport_location" "this" {
  name = var.provider0_location
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
# Creates a Hosted Connection in the customer AWS account via provider0.
# connect_type = "AWSHC" → Hosted Connection (vs "AWS" for dedicated VIF).

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
      owner_account = var.aws_account_id
      amazon_asn    = 64512
      asn           = var.bgp_asn_customer
      auth_key      = var.bgp_auth_key != "" ? var.bgp_auth_key : null
      connect_type  = "AWSHC"
    }
  }
}

# --- Accept the Hosted Private VIF in the customer AWS account ---
# Megaport (as owner) creates the Hosted Private VIF pointing at our DX Gateway.
# We accept it on the customer side.

resource "aws_dx_hosted_private_virtual_interface_accepter" "this" {
  virtual_interface_id = megaport_vxc.aws_dx.b_end.current_product_uid
  dx_gateway_id        = var.aws_dx_gateway_id

  depends_on = [megaport_vxc.aws_dx]
}
