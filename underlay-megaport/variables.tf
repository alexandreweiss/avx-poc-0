# --- provider0 credentials ---

variable "provider0_access_key" {
  description = "provider0 API access key"
  type        = string
  sensitive   = true
}

variable "provider0_secret_key" {
  description = "provider0 API secret key"
  type        = string
  sensitive   = true
}

# --- Port ---

variable "provider0_location" {
  description = "provider0 datacenter location name for the port (e.g. 'Equinix LD5'). Run: terraform plan and check provider0_location data source for available names near eu-west-1."
  type        = string
  default     = "Equinix LD5"
}

variable "port_name" {
  description = "Name for the provider0 port"
  type        = string
  default     = "poc-al-port-dublin"
}

variable "port_speed" {
  description = "Port speed in Mbps (1000, 10000)"
  type        = number
  default     = 1000
}

variable "port_term" {
  description = "Port contract term in months (1, 12, 24)"
  type        = number
  default     = 1
}

# --- VXC to AWS DX ---

variable "vxc_name" {
  description = "Name for the VXC connecting the port to AWS DX"
  type        = string
  default     = "poc-al-to-aws-dublin"
}

variable "vxc_bandwidth" {
  description = "VXC bandwidth in Mbps"
  type        = number
  default     = 50
}

variable "aws_account_id" {
  description = "AWS account ID that owns the DX gateway (used for Hosted Connection request)"
  type        = string
  default     = "211098808963"
}

variable "aws_region" {
  description = "AWS region for DX connection"
  type        = string
  default     = "eu-west-1"
}

variable "aws_dx_gateway_id" {
  description = "DX Gateway ID from main architecture (output of root module dx_gateway_id)"
  type        = string
}

variable "vlan" {
  description = "VLAN ID for the VXC (1-4093). Must match the Private VIF VLAN."
  type        = number
  default     = 100
}

# --- Private VIF / BGP ---

variable "bgp_asn_customer" {
  description = "BGP ASN for the AL/customer side"
  type        = number
  default     = 65000
}

variable "bgp_auth_key" {
  description = "BGP MD5 auth key shared between AWS and provider0"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vif_name" {
  description = "Name for the Private VIF"
  type        = string
  default     = "poc-al-private-vif"
}
