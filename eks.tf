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

# NAT gateway — nodes pull images and pods reach internet before Aviatrix attachment
resource "aws_eip" "eks_nat" {
  count  = var.deploy_eks ? 1 : 0
  domain = "vpc"
  tags   = { Name = "spoke-eks-nat-eip" }
}

resource "aws_nat_gateway" "eks" {
  count         = var.deploy_eks ? 1 : 0
  allocation_id = aws_eip.eks_nat[0].id
  subnet_id     = aws_subnet.eks_public[0].id
  tags          = { Name = "spoke-eks-nat" }
  depends_on    = [aws_internet_gateway.eks]
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
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks[0].id
  }
  tags = { Name = "spoke-eks-private-rt-${count.index}" }
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

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# VPC CNI addon — each pod gets a real VPC IP from the subnet CIDR
resource "aws_eks_addon" "vpc_cni" {
  count        = var.deploy_eks ? 1 : 0
  cluster_name = aws_eks_cluster.this[0].name
  addon_name   = "vpc-cni"
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
  ]
}

# --- Aviatrix spoke in EKS VPC ---
# Deploys into the public subnet; controller programs VPC routes after attachment.

resource "aviatrix_spoke_gateway" "eks" {
  count        = var.deploy_eks ? 1 : 0
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "spoke-eks-gw"
  vpc_id       = aws_vpc.eks[0].id
  vpc_reg      = var.aws_region
  gw_size      = var.spoke_aws_gw_size
  subnet       = aws_subnet.eks_public[0].cidr_block

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
  ]
}
