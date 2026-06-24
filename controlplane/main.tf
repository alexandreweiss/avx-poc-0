module "control_plane" {
  source  = "terraform-aviatrix-modules/aws-controlplane/aviatrix"
  version = "1.0.12"

  controller_name           = var.controller_name
  controller_instance_type  = var.controller_instance_type
  controller_version        = var.controller_version
  controller_admin_email    = var.controller_admin_email
  controller_admin_password = var.controller_admin_password
  customer_id               = var.customer_id
  access_account_name       = var.access_account_name
  account_email             = var.account_email
  incoming_ssl_cidrs        = var.incoming_ssl_cidrs
  controlplane_vpc_cidr     = var.controlplane_vpc_cidr
  controlplane_subnet_cidr  = var.controlplane_subnet_cidr

  module_config = {
    controller_deployment     = true
    controller_initialization = true
    copilot_deployment        = true
    copilot_initialization    = true
    iam_roles                 = var.create_iam_roles
    account_onboarding        = true
  }
}
