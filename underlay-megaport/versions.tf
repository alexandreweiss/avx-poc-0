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
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 9.0"
    }
  }
}

provider "megaport" {
  access_key            = var.provider0_access_key
  secret_key            = var.provider0_secret_key
  accept_purchase_terms = true
  environment           = "production"
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aviatrix" {
  controller_ip = var.aviatrix_controller_ip
  username      = var.aviatrix_username
  password      = var.aviatrix_password
}
