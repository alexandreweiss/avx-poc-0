# --- Aviatrix User VPN (optional) ---
# Split-tunnel: only spoke + EKS CIDRs routed through tunnel.
# VPN gateway deployed in spoke-aws1 VPC — already attached to transit,
# transit distributes routes to all spokes and EKS.

resource "aviatrix_gateway" "vpn" {
  count        = var.deploy_vpn ? 1 : 0
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "vpn-gw"
  vpc_id       = aviatrix_vpc.spoke_aws1.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.vpn_gw_size
  subnet       = aviatrix_vpc.spoke_aws1.public_subnets[1].cidr

  vpn_access   = true
  vpn_cidr     = var.vpn_client_cidr
  split_tunnel = true

  additional_cidrs = join(",", compact([
    var.transit_aws_cidr,
    var.spoke_aws1_cidr,
    var.spoke_aws2_cidr,
    var.deploy_eks ? var.eks_cidr : "",
    var.deploy_gcp ? var.spoke_gcp_cidr : "",
  ]))
}

resource "aviatrix_vpn_user" "al_user" {
  count      = var.deploy_vpn && var.vpn_user_email != "" ? 1 : 0
  gw_name    = aviatrix_gateway.vpn[0].gw_name
  user_name  = "al-user"
  user_email = var.vpn_user_email
  vpc_id     = aviatrix_vpc.spoke_aws1.vpc_id
}
