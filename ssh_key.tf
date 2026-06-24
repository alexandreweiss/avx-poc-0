resource "tls_private_key" "spoke_vms" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "spoke_vms_private_key" {
  content         = tls_private_key.spoke_vms.private_key_pem
  filename        = "${path.module}/spoke-vms.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "spoke_vms" {
  key_name   = "poc-spoke-vms"
  public_key = tls_private_key.spoke_vms.public_key_openssh
}
