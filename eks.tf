data "aws_caller_identity" "current" {}

# --- EKS VPC (native AWS resources for full subnet-tag control) ---

resource "aws_vpc" "eks" {
  count                = var.deploy_eks ? 1 : 0
  cidr_block           = var.eks_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "spoke-eks-vpc" }
}

resource "aws_internet_gateway" "eks" {
  count  = var.deploy_eks ? 1 : 0
  vpc_id = aws_vpc.eks[0].id
  tags   = { Name = "spoke-eks-igw" }
}

# Two private subnets (different AZs) — EKS nodes + VPC CNI pod IPs
resource "aws_subnet" "eks_private" {
  count             = var.deploy_eks ? 2 : 0
  vpc_id            = aws_vpc.eks[0].id
  cidr_block        = cidrsubnet(var.eks_cidr, 2, count.index)
  availability_zone = "${var.aws_region}${count.index == 0 ? "a" : "b"}"

  tags = {
    Name                                       = "spoke-eks-private-${count.index}"
    "kubernetes.io/cluster/spoke-eks-cluster"  = "shared"
    "kubernetes.io/role/internal-elb"          = "1"
  }
}

# Public subnet for Aviatrix spoke gateway + NAT gateway
resource "aws_subnet" "eks_public" {
  count                   = var.deploy_eks ? 1 : 0
  vpc_id                  = aws_vpc.eks[0].id
  cidr_block              = cidrsubnet(var.eks_cidr, 2, 2)
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name                                       = "spoke-eks-public"
    "kubernetes.io/cluster/spoke-eks-cluster"  = "shared"
    "kubernetes.io/role/elb"                   = "1"
  }
}

resource "aws_route_table" "eks_public" {
  count  = var.deploy_eks ? 1 : 0
  vpc_id = aws_vpc.eks[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks[0].id
  }
  tags = { Name = "spoke-eks-public-rt" }
}

resource "aws_route_table_association" "eks_public" {
  count          = var.deploy_eks ? 1 : 0
  subnet_id      = aws_subnet.eks_public[0].id
  route_table_id = aws_route_table.eks_public[0].id
}

resource "aws_route_table" "eks_private" {
  count  = var.deploy_eks ? 2 : 0
  vpc_id = aws_vpc.eks[0].id
  tags   = { Name = "spoke-eks-private-rt-${count.index}" }
}

resource "aws_route_table_association" "eks_private" {
  count          = var.deploy_eks ? 2 : 0
  subnet_id      = aws_subnet.eks_private[count.index].id
  route_table_id = aws_route_table.eks_private[count.index].id
}

# --- IAM roles ---

resource "aws_iam_role" "eks_cluster" {
  count = var.deploy_eks ? 1 : 0
  name  = "spoke-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.deploy_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_iam_role" "eks_nodes" {
  count = var.deploy_eks ? 1 : 0
  name  = "spoke-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  count      = var.deploy_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count      = var.deploy_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  count      = var.deploy_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes[0].name
}

# --- EKS Cluster ---

resource "aws_eks_cluster" "this" {
  count    = var.deploy_eks ? 1 : 0
  name     = "spoke-eks-cluster"
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = "1.32"

  vpc_config {
    subnet_ids = concat(
      aws_subnet.eks_private[*].id,
      aws_subnet.eks_public[*].id,
    )
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# VPC CNI addon — each pod gets a real VPC IP from the subnet CIDR
resource "aws_eks_addon" "vpc_cni" {
  count        = var.deploy_eks ? 1 : 0
  cluster_name = aws_eks_cluster.this[0].name
  addon_name   = "vpc-cni"
}

# Disable VPC CNI SNAT so pods use their real VPC IP as source (not node IP).
# ConfigMap approach doesn't propagate — must patch the aws-node DaemonSet env directly.
resource "kubernetes_env" "vpc_cni_disable_snat" {
  count       = var.deploy_eks ? 1 : 0
  api_version = "apps/v1"
  kind        = "DaemonSet"
  metadata {
    name      = "aws-node"
    namespace = "kube-system"
  }
  container = "aws-node"
  force     = true
  env {
    name  = "AWS_VPC_K8S_CNI_EXTERNALSNAT"
    value = "true"
  }
  depends_on = [aws_eks_addon.vpc_cni]
}

resource "aws_eks_node_group" "this" {
  count           = var.deploy_eks ? 1 : 0
  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "spoke-eks-nodes"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.eks_private[*].id
  instance_types  = [var.eks_node_instance_type]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
    aws_eks_addon.vpc_cni,
    aviatrix_spoke_transit_attachment.eks,
  ]
}

# --- Aviatrix Controller EKS access (API auth mode) ---
# Grants Controller's IAM roles read access via EKS Access Entries (no aws-auth required).

resource "aws_eks_access_entry" "aviatrix_app" {
  count             = var.deploy_eks ? 1 : 0
  cluster_name      = aws_eks_cluster.this[0].name
  principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aviatrix-role-app"
  kubernetes_groups = ["avx-controller"]
  type              = "STANDARD"
  depends_on        = [aws_eks_cluster.this]
}

resource "aws_eks_access_policy_association" "aviatrix_app" {
  count         = var.deploy_eks ? 1 : 0
  cluster_name  = aws_eks_cluster.this[0].name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aviatrix-role-app"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.aviatrix_app]
}

resource "aws_eks_access_entry" "aviatrix_ec2" {
  count             = var.deploy_eks ? 1 : 0
  cluster_name      = aws_eks_cluster.this[0].name
  principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aviatrix-role-ec2"
  kubernetes_groups = ["avx-controller"]
  type              = "STANDARD"
  depends_on        = [aws_eks_cluster.this]
}

resource "aws_eks_access_policy_association" "aviatrix_ec2" {
  count         = var.deploy_eks ? 1 : 0
  cluster_name  = aws_eks_cluster.this[0].name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aviatrix-role-ec2"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.aviatrix_ec2]
}

# Grant the Terraform deployer (current IAM caller) cluster-admin via API access entry.
# Required so the kubernetes/helm providers can authenticate after cluster creation.
resource "aws_eks_access_entry" "deployer" {
  count        = var.deploy_eks ? 1 : 0
  cluster_name = aws_eks_cluster.this[0].name
  principal_arn = data.aws_caller_identity.current.arn
  type         = "STANDARD"
  depends_on   = [aws_eks_cluster.this]
}

resource "aws_eks_access_policy_association" "deployer" {
  count         = var.deploy_eks ? 1 : 0
  cluster_name  = aws_eks_cluster.this[0].name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_caller_identity.current.arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.deployer]
}

# --- Allow inbound to cluster SG from spoke CIDRs (VPN gw SNAT + transit) ---
# VPN clients appear as VPN gw private IP; spokes reach pods directly via Aviatrix.

resource "aws_security_group_rule" "eks_ingress_from_spokes" {
  count             = var.deploy_eks ? 1 : 0
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [
    var.transit_aws_cidr,
    var.spoke_aws1_cidr,
    var.spoke_aws2_cidr,
  ]
  security_group_id = aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id
  description       = "Allow all traffic from AWS transit and spokes (includes VPN gw SNAT)"
}

# --- Aviatrix spoke in EKS VPC ---
# Deploys into the public subnet; controller programs VPC routes after attachment.

resource "aviatrix_spoke_gateway" "eks" {
  count          = var.deploy_eks ? 1 : 0
  cloud_type     = 1
  account_name   = var.aws_account_name
  gw_name        = "spoke-eks-gw"
  vpc_id         = aws_vpc.eks[0].id
  vpc_reg        = var.aws_region
  gw_size        = var.spoke_aws_gw_size
  subnet         = aws_subnet.eks_public[0].cidr_block
  single_ip_snat = true

  depends_on = [aws_route_table_association.eks_public]
}

resource "aviatrix_spoke_transit_attachment" "eks" {
  count           = var.deploy_eks ? 1 : 0
  spoke_gw_name   = aviatrix_spoke_gateway.eks[0].gw_name
  transit_gw_name = module.transit_aws.transit_gateway.gw_name
}

# --- Enable k8s feature on the controller (required for k8s smart groups) ---

resource "aviatrix_config_feature" "k8s" {
  count        = var.deploy_eks ? 1 : 0
  feature_name = "k8s"
  is_enabled   = true
}

resource "aviatrix_config_feature" "k8s_dcf_policies" {
  count        = var.deploy_eks ? 1 : 0
  feature_name = "k8s_dcf_policies"
  is_enabled   = true
  depends_on   = [aviatrix_config_feature.k8s]
}

# --- Install Aviatrix k8s-firewall Helm chart ---
# Installs CRDs (FirewallPolicy + WebgroupPolicy) and the avx-controller ClusterRole/Binding.
# Must run BEFORE aviatrix_kubernetes_cluster — controller fetcher checks for CRDs on first connect
# and caches failure permanently if they are absent (requires controller restart to clear).

resource "helm_release" "k8s_firewall" {
  count      = var.deploy_eks ? 1 : 0
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"

  depends_on = [
    aws_eks_node_group.this,
    kubernetes_cluster_role_binding.aviatrix_controller,
  ]
}

# --- Onboard EKS cluster into Aviatrix Controller ---
# cluster_id = EKS cluster ARN
# use_csp_credentials = true  →  reuses the onboarded AWS account credentials
# network_mode = FLAT  →  VPC CNI, each pod has a real VPC IP

resource "aviatrix_kubernetes_cluster" "eks" {
  count              = var.deploy_eks ? 1 : 0
  cluster_id         = aws_eks_cluster.this[0].arn
  use_csp_credentials = true

  cluster_details {
    name                 = aws_eks_cluster.this[0].name
    account_name         = var.aws_account_name
    account_id           = data.aws_caller_identity.current.account_id
    platform             = "eks"
    network_mode         = "FLAT"
    version              = aws_eks_cluster.this[0].version
    vpc_id               = aws_vpc.eks[0].id
    region               = var.aws_region
    is_publicly_accessible = true
  }

  depends_on = [
    aviatrix_spoke_transit_attachment.eks,
    aviatrix_config_feature.k8s_dcf_policies,
    kubernetes_cluster_role_binding.aviatrix_controller[0],
    aws_eks_access_policy_association.aviatrix_app,
    aws_eks_access_policy_association.aviatrix_ec2,
    helm_release.k8s_firewall,
  ]
}

# --- Grant Aviatrix controller IAM role access to the EKS cluster ---
# Patches aws-auth ConfigMap so the controller's EC2 role can call the k8s API.

resource "kubernetes_config_map_v1_data" "aws_auth" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = yamlencode(concat([
      {
        rolearn  = aws_iam_role.eks_nodes[0].arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
    ],
    var.eks_admin_iam_role != "" ? [{
      rolearn  = var.eks_admin_iam_role
      username = "eks-admin"
      groups   = ["system:masters"]
    }] : []))
  }
  force = true
  depends_on = [aws_eks_cluster.this]
}

# --- RBAC: Grant Aviatrix controller cluster-admin so it can install CRDs and deploy enforcement components ---

resource "kubernetes_cluster_role_binding" "aviatrix_controller" {
  count = var.deploy_eks ? 1 : 0
  metadata { name = "aviatrix-controller" }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "avx-controller"
    api_group = "rbac.authorization.k8s.io"
  }
}
