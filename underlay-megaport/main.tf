# provider0 underlay for AWS Direct Connect via Aviatrix Edge MVE
#
# Deploys:
#   1. Aviatrix Secure Edge on Megaport MVE (Equinix Washington DC4)
#   2. VXC from MVE to AWS DX partner port (us-east-1)
#   3. Accepts the Hosted Private VIF in the customer AWS account
#
# Prerequisites (from root module):
#   - aws_dx_gateway already exists (var.aws_dx_gateway_id)
#   - VGW already associated with that DX Gateway
#   - Aviatrix Controller reachable at var.aviatrix_controller_ip
#     (MVE cloud-init registers the Edge gateway with the Controller)
#
# To replace with another underlay provider: delete this directory and create
# underlay-<provider>/ with the same var.aws_dx_gateway_id input.

# --- Discover provider0 location ---

data "megaport_location" "this" {
  name = var.provider0_location
}

# --- AWS DX partner port at the same location (us-east-1) ---

data "megaport_partner" "aws_dx" {
  connect_type = "AWSHC"
  company_name = "AWS"
  product_name = "US East (N. Virginia) (us-east-1)"
  location_id  = data.megaport_location.this.id
}

# --- Aviatrix Secure Edge MVE ---
# cloud_init bootstraps the Edge and registers it with the Aviatrix Controller.
# The Controller issues a token; encode it as base64 cloud-init.

resource "megaport_mve" "aviatrix_edge" {
  product_name         = var.mve_name
  location_id          = data.megaport_location.this.id
  contract_term_months = var.port_term

  vendor_config = {
    vendor       = "aviatrix"
    image_id     = 177  # Aviatrix Secure Edge g4-202605062026
    product_size = var.mve_size
    cloud_init   = base64encode(templatefile("${path.module}/cloud_init.tpl", {
      controller_ip    = var.aviatrix_controller_ip
      controller_token = var.aviatrix_edge_token
      gateway_name     = var.aviatrix_edge_gw_name
    }))
  }

  vnics = [
    { description = "WAN" },
    { description = "LAN" },
  ]
}

# --- VXC from Aviatrix Edge MVE to AWS DX (Hosted Connection) ---

resource "megaport_vxc" "aws_dx" {
  product_name         = var.vxc_name
  rate_limit           = var.vxc_bandwidth
  contract_term_months = var.port_term

  a_end = {
    requested_product_uid = megaport_mve.aviatrix_edge.product_uid
    ordered_vlan          = var.vlan
    vnic_index            = 0  # WAN interface
  }

  b_end = {
    requested_product_uid = data.megaport_partner.aws_dx.product_uid
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

resource "aws_dx_hosted_private_virtual_interface_accepter" "this" {
  virtual_interface_id = megaport_vxc.aws_dx.b_end.current_product_uid
  dx_gateway_id        = var.aws_dx_gateway_id

  depends_on = [megaport_vxc.aws_dx]
}
