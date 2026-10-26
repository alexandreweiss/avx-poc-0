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

# Smart group for EKS nodes — VM type matched by EKS cluster tag.
# EKS managed node groups automatically tag instances with eks:cluster-name.
# CIDR-based matching proved unreliable for egress DCF on spoke gateways (tested).
# Does NOT depend on k8s cluster onboarding — tag exists on EC2 before kubelet joins.

resource "aviatrix_smart_group" "eks_nodes" {
  count = var.deploy_eks ? 1 : 0
  name  = "eks-nodes"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        "eks:cluster-name" = "spoke-eks-cluster"
      }
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
      k8s_cluster_id = aws_eks_cluster.this[0].arn
      k8s_namespace  = "gatus-aviatrix"
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

resource "aviatrix_smart_group" "eks_all_pods" {
  count = var.deploy_eks ? 1 : 0
  name  = "eks-all-pods"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = aws_eks_cluster.this[0].arn
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.this]
}

# --- Webgroups for URL-level DCF filtering (requires TLS inspection on spoke GW) ---
# Both paths share SNI "github.com" — urlfilter differentiates at URL level post-decryption.

resource "aviatrix_web_group" "github_aviatrixsystems" {
  count = var.deploy_eks ? 1 : 0
  name  = "url-github-aviatrixsystems"

  selector {
    match_expressions {
      urlfilter = "github.com/AviatrixSystems"
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

  # Priority 220 — AFTER Gatus policies (210/211). Pods share node subnet (VPC CNI),
  # so this CIDR rule must be lower priority than Gatus k8s smart group rules.
  dynamic "policies" {
    for_each = var.deploy_eks ? [1] : []
    content {
      name     = "allow-eks-nodes-egress"
      action   = "PERMIT"
      priority = 221
      protocol = "ANY"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.eks_nodes[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]
    }
  }

  # Spoke VMs egress to internet — required for bootstrap (apt-get) and nginx operation.
  # Traffic flows through the spoke gateway (single_ip_snat=true); DCF inspects it here.
  policies {
    name     = "allow-spoke-vms-egress"
    action   = "PERMIT"
    priority = 70
    protocol = "TCP"
    logging  = true

    src_smart_groups = [
      aviatrix_smart_group.spoke_aws1.uuid,
      aviatrix_smart_group.spoke_aws2.uuid,
    ]
    dst_smart_groups = [var.public_internet_smartgroup_uuid]

    port_ranges {
      lo = 80
      hi = 80
    }
    port_ranges {
      lo = 443
      hi = 443
    }
  }

  dynamic "policies" {
    for_each = var.deploy_gcp ? [1] : []
    content {
      name     = "allow-spoke-gcp-egress"
      action   = "PERMIT"
      priority = 71
      protocol = "TCP"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.spoke_gcp[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]

      port_ranges {
        lo = 80
        hi = 80
      }
      port_ranges {
        lo = 443
        hi = 443
      }
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


  # Policy 211: PERMIT gatus-aviatrix → github.com/AviatrixSystems
  dynamic "policies" {
    for_each = var.deploy_eks ? [1] : []
    content {
      name           = "permit-gatus-aviatrix-github"
      action         = "PERMIT"
      priority       = 211
      protocol       = "TCP"
      logging        = true
      decrypt_policy = "DECRYPT_ALLOWED"

      src_smart_groups = [aviatrix_smart_group.gatus_aviatrix[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]
      web_groups       = [aviatrix_web_group.github_aviatrixsystems[0].uuid]

      port_ranges {
        lo = 443
        hi = 443
      }
    }
  }

  # Policy 212: DENY all EKS pods → internet (default web deny; rule 211 permits gatus-aviatrix first)
  dynamic "policies" {
    for_each = var.deploy_eks ? [1] : []
    content {
      name     = "deny-eks-pods-internet"
      action   = "DENY"
      priority = 212
      protocol = "TCP"
      logging  = true

      src_smart_groups = [aviatrix_smart_group.eks_all_pods[0].uuid]
      dst_smart_groups = [var.public_internet_smartgroup_uuid]

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

  # Re-applied after EKS spoke is attached so controller knows spoke CIDR when pushing rules.
  # Fixes CIDR-based smart group not propagating to spoke-eks-gw.
  depends_on = [aviatrix_spoke_transit_attachment.eks]
}
