output "provider0_port_uid" {
  description = "provider0 Port product UID"
  value       = megaport_port.this.product_uid
}

output "provider0_vxc_uid" {
  description = "provider0 VXC product UID"
  value       = megaport_vxc.aws_dx.product_uid
}

output "dx_hosted_vif_id" {
  description = "AWS Hosted Private VIF ID (accepted)"
  value       = aws_dx_hosted_private_virtual_interface_accepter.this.id
}

output "bgp_status_check" {
  description = "CLI command to check VIF BGP state"
  value       = "aws directconnect describe-virtual-interfaces --virtual-interface-id ${aws_dx_hosted_private_virtual_interface_accepter.this.virtual_interface_id} --region ${var.aws_region} --query 'virtualInterfaces[0].{state:virtualInterfaceState,bgpPeers:bgpPeers}'"
}
