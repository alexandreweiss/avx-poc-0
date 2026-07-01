# --- provider0 credentials ---

variable "provider0_access_key" {
  description = "provider0 API M2M client ID"
  type        = string
  sensitive   = true
}

variable "provider0_secret_key" {
  description = "provider0 API M2M client secret"
  type        = string
  sensitive   = true
}

# --- MVE ---

variable "provider0_location" {
  description = "provider0 datacenter location name. Must match exact Megaport name. DC4: 'Equinix Washington DC4' (ID 67). NY9: 'Equinix New York NY9' (ID 61)."
  type        = string
  default     = "Equinix Washington DC4"
}

variable "mve_name" {
  description = "Name for the Aviatrix Edge MVE"
  type        = string
  default     = "poc-al-avx-edge"
}

variable "mve_size" {
  description = "MVE size: MEDIUM (4 vCPU/16GB) or LARGE (8 vCPU/32GB)"
  type        = string
  default     = "MEDIUM"
}

variable "port_term" {
  description = "Contract term in months (1, 12, 24)"
  type        = number
  default     = 1
}

# --- Aviatrix Controller ---

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP or FQDN"
  type        = string
  default     = "54.75.173.51"
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

variable "aviatrix_account_name" {
  description = "Megaport access account name onboarded in the Aviatrix Controller"
  type        = string
  default     = "mp"
}

variable "aviatrix_site_id" {
  description = "Aviatrix Edge platform site ID (the platform name created in CoPilot)"
  type        = string
  default     = "mp"
}

variable "aviatrix_edge_gw_name" {
  description = "Name for the Aviatrix Edge gateway"
  type        = string
  default     = "edge-megaport-us"
}

# --- VXC to AWS DX ---

variable "vxc_name" {
  description = "Name for the VXC connecting the MVE to AWS DX"
  type        = string
  default     = "poc-al-edge-to-aws"
}

variable "vxc_bandwidth" {
  description = "VXC bandwidth in Mbps"
  type        = number
  default     = 50
}

variable "aws_account_id" {
  description = "AWS account ID that owns the DX gateway"
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
  description = "VLAN ID for the VXC and Private VIF (1-4093)"
  type        = number
  default     = 100
}

# --- BGP ---

variable "bgp_asn_customer" {
  description = "BGP ASN for the AL/Edge side"
  type        = number
  default     = 65000
}

variable "bgp_auth_key" {
  description = "BGP MD5 auth key shared between AWS and Aviatrix Edge"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vif_name" {
  description = "Name for the Private VIF"
  type        = string
  default     = "poc-al-private-vif"
}

variable "wan_ip" {
  description = "WAN interface IP/prefix for the Edge gateway (e.g. 1.2.3.4/30). Assigned by Megaport after MVE is live."
  type        = string
}

variable "wan_gateway_ip" {
  description = "WAN default gateway IP"
  type        = string
}

variable "wan_public_ip" {
  description = "WAN public IP (same as wan_ip host address for Megaport-assigned IPs)"
  type        = string
}

variable "aws_dx_hosted_connection_id" {
  description = "AWS hosted connection ID provisioned by Megaport (dxcon-xxxxxxxx). Visible in AWS Console → Direct Connect → Connections after VXC is live."
  type        = string
  default     = ""
}
