# Smart groups for each spoke workload

resource "aviatrix_smart_group" "spoke_aws1" {
  name = "spoke-aws1-vms"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Spoke = "aws1"
      }
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

resource "aviatrix_smart_group" "spoke_aws2" {
  name = "spoke-aws2-vms"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Spoke = "aws2"
      }
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

resource "aviatrix_smart_group" "spoke_gcp" {
  count = var.deploy_gcp ? 1 : 0
  name  = "spoke-gcp-vms"

  selector {
    match_expressions {
      cidr = var.spoke_gcp_cidr
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

# DCF policy list: allow east-west between all spokes, allow HTTP/HTTPS out

locals {
  gcp_sg_uuid = var.deploy_gcp ? aviatrix_smart_group.spoke_gcp[0].uuid : null

  gcp_policies = var.deploy_gcp ? [
    {
      name     = "allow-aws1-to-gcp"
      priority = 102
      src      = aviatrix_smart_group.spoke_aws1.uuid
      dst      = local.gcp_sg_uuid
    },
    {
      name     = "allow-gcp-to-aws1"
      priority = 103
      src      = local.gcp_sg_uuid
      dst      = aviatrix_smart_group.spoke_aws1.uuid
    },
    {
      name     = "allow-aws2-to-gcp"
      priority = 104
      src      = aviatrix_smart_group.spoke_aws2.uuid
      dst      = local.gcp_sg_uuid
    },
    {
      name     = "allow-gcp-to-aws2"
      priority = 105
      src      = local.gcp_sg_uuid
      dst      = aviatrix_smart_group.spoke_aws2.uuid
    },
  ] : []
}

resource "aviatrix_distributed_firewalling_policy_list" "poc" {
  policies {
    name     = "allow-aws1-to-aws2"
    action   = "PERMIT"
    priority = 100
    protocol = "ANY"
    logging  = true

    src_smart_groups = [aviatrix_smart_group.spoke_aws1.uuid]
    dst_smart_groups = [aviatrix_smart_group.spoke_aws2.uuid]
  }

  policies {
    name     = "allow-aws2-to-aws1"
    action   = "PERMIT"
    priority = 101
    protocol = "ANY"
    logging  = true

    src_smart_groups = [aviatrix_smart_group.spoke_aws2.uuid]
    dst_smart_groups = [aviatrix_smart_group.spoke_aws1.uuid]
  }

  dynamic "policies" {
    for_each = local.gcp_policies
    content {
      name     = policies.value.name
      action   = "PERMIT"
      priority = policies.value.priority
      protocol = "ANY"
      logging  = true

      src_smart_groups = [policies.value.src]
      dst_smart_groups = [policies.value.dst]
    }
  }

  policies {
    name     = "allow-spokes-egress-http"
    action   = "PERMIT"
    priority = 200
    protocol = "TCP"
    logging  = true

    src_smart_groups = [var.anywhere_smartgroup_uuid]
    dst_smart_groups = [var.public_internet_smartgroup_uuid]
    web_groups       = [var.allweb_webgroup_uuid]

    port_ranges {
      lo = 80
      hi = 80
    }
  }

  policies {
    name     = "allow-spokes-egress-https"
    action   = "PERMIT"
    priority = 201
    protocol = "TCP"
    logging  = true

    src_smart_groups = [var.anywhere_smartgroup_uuid]
    dst_smart_groups = [var.public_internet_smartgroup_uuid]
    web_groups       = [var.allweb_webgroup_uuid]

    port_ranges {
      lo = 443
      hi = 443
    }
  }

  policies {
    name     = "default-deny"
    action   = "DENY"
    priority = 65000
    protocol = "ANY"
    logging  = true

    src_smart_groups = [var.anywhere_smartgroup_uuid]
    dst_smart_groups = [var.anywhere_smartgroup_uuid]
  }
}
