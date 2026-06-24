variable "aws_region" {
  description = "AWS region — must match the PoC transit region (eu-west-1 for Dublin)"
  type        = string
  default     = "eu-west-1"
}

variable "controller_name" {
  description = "Name tag for the Controller EC2 instance"
  type        = string
  default     = "aviatrix-controller"
}

variable "controller_instance_type" {
  description = "EC2 instance type for the Controller"
  type        = string
  default     = "t3.large"
}

variable "controller_version" {
  description = "Aviatrix Controller version to bootstrap"
  type        = string
  default     = "latest"
}

variable "controller_admin_email" {
  description = "Admin email address for the Controller"
  type        = string
}

variable "controller_admin_password" {
  description = "Admin password for the Controller"
  type        = string
  sensitive   = true
}

variable "customer_id" {
  description = "Aviatrix customer license ID (format: xxxxxxx-abu-xxxxxxxxx)"
  type        = string
  sensitive   = true
}

variable "access_account_name" {
  description = "Name for the AWS access account created in the Controller"
  type        = string
  default     = "aws-poc"
}

variable "account_email" {
  description = "Email address for the Aviatrix access account"
  type        = string
}

variable "incoming_ssl_cidrs" {
  description = "CIDRs allowed to reach the Controller on port 443 (include your public IP)"
  type        = list(string)
}

variable "controlplane_vpc_cidr" {
  description = "VPC CIDR for the control plane VPC"
  type        = string
  default     = "10.0.0.0/24"
}

variable "controlplane_subnet_cidr" {
  description = "Subnet CIDR within the control plane VPC"
  type        = string
  default     = "10.0.0.0/24"
}

variable "create_iam_roles" {
  description = "Set false if aviatrix-role-ec2 and aviatrix-role-app already exist in this AWS account"
  type        = bool
  default     = true
}
