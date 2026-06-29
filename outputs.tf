output "ssh_private_key_path" {
  description = "Path to generated SSH private key for spoke VMs"
  value       = local_sensitive_file.spoke_vms_private_key.filename
}

output "ssh_connect_aws1" {
  description = "SSH command for AWS Spoke 1 VM"
  value       = "ssh -i spoke-vms.pem ubuntu@${aws_instance.spoke_aws1.public_ip}"
}

output "ssh_connect_aws2" {
  description = "SSH command for AWS Spoke 2 VM"
  value       = "ssh -i spoke-vms.pem ubuntu@${aws_instance.spoke_aws2.public_ip}"
}

output "ssh_connect_gcp" {
  description = "SSH command for GCP Spoke VM"
  value       = var.deploy_gcp ? "ssh -i spoke-vms.pem ubuntu@${google_compute_instance.spoke_gcp[0].network_interface[0].access_config[0].nat_ip}" : "not deployed"
}

output "nginx_url_aws1" {
  description = "Nginx URL for AWS Spoke 1 VM"
  value       = "http://${aws_instance.spoke_aws1.public_ip}"
}

output "nginx_url_aws2" {
  description = "Nginx URL for AWS Spoke 2 VM"
  value       = "http://${aws_instance.spoke_aws2.public_ip}"
}

output "nginx_url_gcp" {
  description = "Nginx URL for GCP Spoke VM"
  value       = var.deploy_gcp ? "http://${google_compute_instance.spoke_gcp[0].network_interface[0].access_config[0].nat_ip}" : "not deployed"
}

output "transit_aws_gw_name" {
  description = "AWS Transit gateway name"
  value       = module.transit_aws.transit_gateway.gw_name
  sensitive   = true
}

output "transit_gcp_gw_name" {
  description = "GCP Transit gateway name"
  value       = var.deploy_gcp ? module.transit_gcp[0].transit_gateway.gw_name : "not deployed"
  sensitive   = true
}

output "dx_gateway_id" {
  description = "AWS Direct Connect Gateway ID (if deployed)"
  value       = var.deploy_dx_gateway ? aws_dx_gateway.this[0].id : "not deployed"
}

output "gcp_interconnect_pairing_key" {
  description = "GCP Partner Interconnect pairing key to provide to partner (if deployed)"
  value       = var.deploy_gcp_interconnect ? google_compute_interconnect_attachment.partner[0].pairing_key : "not deployed"
}
