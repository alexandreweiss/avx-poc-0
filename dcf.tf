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

# Smart group for VPN clients (CIDR-based)

resource "aviatrix_smart_group" "vpn_clients" {
  count = var.deploy_vpn ? 1 : 0
  name  = "vpn-clients"

  selector {
    match_expressions {
      cidr = "${aviatrix_gateway.vpn[0].private_ip}/32"
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

# Smart group for EKS nodes (by cluster tag — covers all node groups)

resource "aviatrix_smart_group" "eks_nodes" {
  count = var.deploy_eks ? 1 : 0
  name  = "eks-nodes"

  selector {
    match_expressions {
      type           = "k8s_node"
      k8s_cluster_id = aviatrix_kubernetes_cluster.eks[0].cluster_id
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

# --- EKS k8s smart groups (one per Gatus namespace) ---

resource "aviatrix_smart_group" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  name  = "gatus-aviatrix-pods"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = aviatrix_kubernetes_cluster.eks[0].cluster_id
      k8s_namespace  = "gatus-aviatrix"
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

resource "aviatrix_smart_group" "gatus_example" {
  count = var.deploy_eks ? 1 : 0
  name  = "gatus-example-pods"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = aviatrix_kubernetes_cluster.eks[0].cluster_id
      k8s_namespace  = "gatus-example"
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

# --- Webgroups for domain-based DCF filtering ---

resource "aviatrix_web_group" "aviatrix_ai" {
  count = var.deploy_eks ? 1 : 0
  name  = "domain-aviatrix-ai"

  selector {
    match_expressions {
      snifilter = "aviatrix.ai"
    }
  }
}

resource "aviatrix_web_group" "example_com" {
  count = var.deploy_eks ? 1 : 0
  name  = "domain-example-com"

  selector {
    match_expressions {
      snifilter = "www.example.com"
    }
  }
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
  dynamic "policies" {
    for_each = var.deploy_vpn ? [1] : []
    content {
      name     = "allow-vpn-to-spokes"
      action   = "PERMIT"
      priority = 50
      protocol = "ANY"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.vpn_clients[0].uuid]
      dst_smart_groups = [var.anywhere_smartgroup_uuid]
    }
  }

  dynamic "policies" {
    for_each = var.deploy_eks ? [1] : []
    content {
      name     = "allow-eks-nodes-egress"
      action   = "PERMIT"
      priority = 60
      protocol = "ANY"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.eks_nodes[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]
    }
  }

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


  dynamic "policies" {
    for_each = var.deploy_eks ? [1] : []
    content {
      name     = "deny-gatus-aviatrix-ai"
      action   = "DENY"
      priority = 210
      protocol = "TCP"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.gatus_aviatrix[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]
      web_groups       = [aviatrix_web_group.aviatrix_ai[0].uuid]

      port_ranges {
        lo = 443
        hi = 443
      }
    }
  }

  dynamic "policies" {
    for_each = var.deploy_eks ? [1] : []
    content {
      name     = "allow-gatus-example-com"
      action   = "PERMIT"
      priority = 211
      protocol = "TCP"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.gatus_example[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]
      web_groups       = [aviatrix_web_group.example_com[0].uuid]

      port_ranges {
        lo = 443
        hi = 443
      }
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
