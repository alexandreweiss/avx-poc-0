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
  name = "spoke-gcp-vms"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.gcp_account_name
      region       = var.gcp_region
      tags = {
        spoke-gcp-vm = ""
      }
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

# DCF policy list: allow east-west between all spokes, allow HTTP/HTTPS out

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

  policies {
    name     = "allow-aws1-to-gcp"
    action   = "PERMIT"
    priority = 102
    protocol = "ANY"
    logging  = true

    src_smart_groups = [aviatrix_smart_group.spoke_aws1.uuid]
    dst_smart_groups = [aviatrix_smart_group.spoke_gcp.uuid]
  }

  policies {
    name     = "allow-gcp-to-aws1"
    action   = "PERMIT"
    priority = 103
    protocol = "ANY"
    logging  = true

    src_smart_groups = [aviatrix_smart_group.spoke_gcp.uuid]
    dst_smart_groups = [aviatrix_smart_group.spoke_aws1.uuid]
  }

  policies {
    name     = "allow-aws2-to-gcp"
    action   = "PERMIT"
    priority = 104
    protocol = "ANY"
    logging  = true

    src_smart_groups = [aviatrix_smart_group.spoke_aws2.uuid]
    dst_smart_groups = [aviatrix_smart_group.spoke_gcp.uuid]
  }

  policies {
    name     = "allow-gcp-to-aws2"
    action   = "PERMIT"
    priority = 105
    protocol = "ANY"
    logging  = true

    src_smart_groups = [aviatrix_smart_group.spoke_gcp.uuid]
    dst_smart_groups = [aviatrix_smart_group.spoke_aws2.uuid]
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
