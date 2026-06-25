# --- Aviatrix Controller ---

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP or hostname"
  type        = string
}

variable "aviatrix_username" {
  description = "Aviatrix Controller admin username"
  type        = string
  default     = "admin"
}

variable "aviatrix_password" {
  description = "Aviatrix Controller admin password"
  type        = string
  sensitive   = true
}

# --- AWS ---

variable "aws_region" {
  description = "AWS region (Dublin)"
  type        = string
  default     = "eu-west-1"
}

variable "aws_account_name" {
  description = "Aviatrix onboarded AWS account name"
  type        = string
}

variable "transit_aws_cidr" {
  description = "AWS transit VPC CIDR"
  type        = string
  default     = "10.10.0.0/23"
}

variable "spoke_aws1_cidr" {
  description = "AWS spoke 1 VPC CIDR"
  type        = string
  default     = "10.20.0.0/23"
}

variable "spoke_aws2_cidr" {
  description = "AWS spoke 2 VPC CIDR"
  type        = string
  default     = "10.21.0.0/23"
}

variable "transit_aws_gw_size" {
  description = "AWS transit gateway instance size"
  type        = string
  default     = "c5.xlarge"
}

variable "spoke_aws_gw_size" {
  description = "AWS spoke gateway instance size"
  type        = string
  default     = "t3.small"
}

variable "spoke_vm_instance_type" {
  description = "EC2 instance type for spoke Ubuntu VMs"
  type        = string
  default     = "t3.micro"
}

# --- GCP ---

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_account_name" {
  description = "Aviatrix onboarded GCP account name"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "europe-west3"
}

variable "transit_gcp_cidr" {
  description = "GCP transit VPC CIDR"
  type        = string
  default     = "10.30.0.0/23"
}

variable "spoke_gcp_cidr" {
  description = "GCP spoke VPC CIDR"
  type        = string
  default     = "10.31.0.0/23"
}

variable "transit_gcp_gw_size" {
  description = "GCP transit gateway instance size"
  type        = string
  default     = "n1-standard-2"
}

variable "spoke_gcp_gw_size" {
  description = "GCP spoke gateway instance size"
  type        = string
  default     = "n1-standard-2"
}

variable "spoke_gcp_vm_type" {
  description = "GCP instance type for spoke Ubuntu VM"
  type        = string
  default     = "e2-micro"
}

# --- DCF ---

variable "allweb_webgroup_uuid" {
  description = "UUID of the AllWeb webgroup for DCF policy"
  type        = string
  default     = "def000ad-0000-0000-0000-000000000002"
}

variable "anywhere_smartgroup_uuid" {
  description = "UUID of the Anywhere smart group"
  type        = string
  default     = "def000ad-0000-0000-0000-000000000000"
}

variable "public_internet_smartgroup_uuid" {
  description = "UUID of the Public Internet smart group"
  type        = string
  default     = "def000ad-0000-0000-0000-000000000001"
}

# --- Optional: AWS Direct Connect Gateway ---

variable "deploy_dx_gateway" {
  description = "Deploy AWS Direct Connect Gateway attached to AWS transit (set true when DX circuit is available)"
  type        = bool
  default     = false
}

variable "dx_gateway_asn" {
  description = "BGP ASN for the AWS Direct Connect Gateway"
  type        = number
  default     = 64512
}

variable "dx_gateway_name" {
  description = "Name for the AWS Direct Connect Gateway"
  type        = string
  default     = "poc-dx-gateway"
}

# --- Optional: GCP Partner Interconnect Gateway ---

variable "deploy_gcp_interconnect" {
  description = "Deploy GCP VLAN attachments for Partner Interconnect (set true when partner circuit is available)"
  type        = bool
  default     = false
}

variable "gcp_interconnect_router_asn" {
  description = "BGP ASN for the GCP Cloud Router used for Partner Interconnect"
  type        = number
  default     = 65000
}

variable "gcp_interconnect_bandwidth" {
  description = "Bandwidth for GCP Partner Interconnect VLAN attachment"
  type        = string
  default     = "BPS_1G"
}

variable "gcp_interconnect_pairing_key" {
  description = "Pairing key from the partner for the VLAN attachment (required when deploy_gcp_interconnect=true)"
  type        = string
  default     = ""
}
