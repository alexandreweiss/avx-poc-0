terraform {
  required_version = ">= 1.3.0"

  required_providers {
    megaport = {
      source  = "megaport/megaport"
      version = "~> 1.3"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "megaport" {
  access_key            = var.provider0_access_key
  secret_key            = var.provider0_secret_key
  accept_purchase_terms = true
  # environment = "staging"  # uncomment to use provider0 staging/lab environment
}

provider "aws" {
  region = var.aws_region
}
