output "controller_public_ip" {
  description = "Controller public IP — use as aviatrix_controller_ip in the root PoC"
  value       = module.control_plane.controller_public_ip
}

output "controller_private_ip" {
  value = module.control_plane.controller_private_ip
}

output "controller_url" {
  description = "Controller UI URL"
  value       = "https://${module.control_plane.controller_public_ip}"
}

output "copilot_public_ip" {
  value = module.control_plane.copilot_public_ip
}

output "copilot_url" {
  description = "CoPilot UI URL"
  value       = "https://${module.control_plane.copilot_public_ip}"
}

output "controller_vpc_id" {
  value = module.control_plane.controller_vpc_id
}

output "access_account_name" {
  description = "Account name onboarded — pass as aws_account_name in root PoC"
  value       = var.access_account_name
}
