provider "aviatrix" {
  controller_ip = var.aviatrix_controller_ip
  username      = var.aviatrix_username
  password      = var.aviatrix_password
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "helm" {
  kubernetes {
    host                   = try(aws_eks_cluster.this[0].endpoint, "")
    cluster_ca_certificate = try(base64decode(aws_eks_cluster.this[0].certificate_authority[0].data), "")

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", try(aws_eks_cluster.this[0].name, "none")]
    }
  }
}
