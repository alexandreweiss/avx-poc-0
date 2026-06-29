output "megaport_port_uid" {
  description = "Megaport Port product UID"
  value       = megaport_port.this.product_uid
}

output "megaport_vxc_uid" {
  description = "Megaport VXC product UID"
  value       = megaport_vxc.aws_dx.product_uid
}

output "dx_connection_id" {
  description = "AWS DX Hosted Connection ID (accepted)"
  value       = megaport_vxc.aws_dx.b_end.product_uid
}

output "private_vif_id" {
  description = "AWS Private VIF ID"
  value       = aws_dx_private_virtual_interface.this.id
}

output "private_vif_state" {
  description = "Private VIF BGP state — should reach 'available' once BGP is up"
  value       = aws_dx_private_virtual_interface.this.jumbo_frame_capable
}

output "bgp_status_check" {
  description = "CLI command to check VIF BGP state"
  value       = "aws directconnect describe-virtual-interfaces --virtual-interface-id ${aws_dx_private_virtual_interface.this.id} --region ${var.aws_region} --query 'virtualInterfaces[0].{state:virtualInterfaceState,bgpPeers:bgpPeers}'"
}
