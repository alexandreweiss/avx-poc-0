output "aviatrix_edge_mve_uid" {
  description = "Aviatrix Edge MVE product UID"
  value       = megaport_mve.aviatrix_edge.product_uid
}

output "provider0_vxc_uid" {
  description = "provider0 VXC product UID"
  value       = megaport_vxc.aws_dx.product_uid
}

output "dx_private_vif_id" {
  description = "AWS Private VIF ID created on the hosted connection"
  value       = var.aws_dx_hosted_connection_id != "" ? aws_dx_private_virtual_interface.this.id : "pending — set aws_dx_hosted_connection_id once VXC is live"
}

output "bgp_status_check" {
  description = "CLI command to check VIF BGP state once VIF is created"
  value       = var.aws_dx_hosted_connection_id != "" ? "aws directconnect describe-virtual-interfaces --virtual-interface-id ${aws_dx_private_virtual_interface.this.id} --region ${var.aws_region} --query 'virtualInterfaces[0].{state:virtualInterfaceState,bgpPeers:bgpPeers}'" : "pending"
}
