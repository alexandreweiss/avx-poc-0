output "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP or hostname"
  value       = var.aviatrix_controller_ip
}

output "ssh_private_key_path" {
  description = "Path to generated SSH private key for spoke VMs"
  value       = local_sensitive_file.spoke_vms_private_key.filename
}

output "ssh_connect_aws1" {
  description = "SSH command for AWS Spoke 1 VM (requires VPN — no public IP)"
  value       = "ssh -i spoke-vms.pem ubuntu@${aws_instance.spoke_aws1.private_ip}"
}

output "ssh_connect_aws2" {
  description = "SSH command for AWS Spoke 2 VM (requires VPN — no public IP)"
  value       = "ssh -i spoke-vms.pem ubuntu@${aws_instance.spoke_aws2.private_ip}"
}

output "ssh_connect_gcp" {
  description = "SSH command for GCP Spoke VM (requires VPN — no public IP)"
  value       = var.deploy_gcp ? "ssh -i spoke-vms.pem ubuntu@${google_compute_instance.spoke_gcp[0].network_interface[0].network_ip}" : "not deployed"
}

output "nginx_url_aws1" {
  description = "Nginx URL for AWS Spoke 1 VM (reachable via VPN)"
  value       = "http://${aws_instance.spoke_aws1.private_ip}"
}

output "nginx_url_aws2" {
  description = "Nginx URL for AWS Spoke 2 VM (reachable via VPN)"
  value       = "http://${aws_instance.spoke_aws2.private_ip}"
}

output "nginx_url_gcp" {
  description = "Nginx URL for GCP Spoke VM (reachable via VPN)"
  value       = var.deploy_gcp ? "http://${google_compute_instance.spoke_gcp[0].network_interface[0].network_ip}" : "not deployed"
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

output "vpn_gateway_ip" {
  description = "VPN gateway public IP — use as server in OpenVPN client profile (if deploy_vpn=true)"
  value       = var.deploy_vpn ? aviatrix_gateway.vpn[0].eip : "not deployed"
}

output "gatus_aviatrix_url" {
  description = "Gatus aviatrix.ai dashboard — reachable via VPN on pod IP:8080 (kubectl get pod -n gatus-aviatrix -o wide)"
  value       = var.deploy_eks ? "http://<pod-ip>:8080  (kubectl get pod -n gatus-aviatrix -o wide)" : "not deployed"
}

output "gatus_example_url" {
  description = "Gatus example.com dashboard — reachable via VPN on pod IP:8080 (kubectl get pod -n gatus-example -o wide)"
  value       = var.deploy_eks ? "http://<pod-ip>:8080  (kubectl get pod -n gatus-example -o wide)" : "not deployed"
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = var.deploy_eks ? aws_eks_cluster.this[0].endpoint : "not deployed"
}

output "eks_kubeconfig_cmd" {
  description = "Command to update kubeconfig for the EKS cluster"
  value       = var.deploy_eks ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this[0].name}" : "not deployed"
}

output "gcp_interconnect_pairing_key" {
  description = "GCP Partner Interconnect pairing key to provide to partner (if deployed)"
  value       = var.deploy_gcp_interconnect ? google_compute_interconnect_attachment.partner[0].pairing_key : "not deployed"
}
