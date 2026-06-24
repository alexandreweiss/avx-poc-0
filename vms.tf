# --- Ubuntu AMI (AWS) ---

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Security Group (shared for both AWS spokes) ---

resource "aws_security_group" "spoke_vms" {
  name        = "poc-spoke-vms-sg"
  description = "SSH + HTTP + RFC1918"
  vpc_id      = aviatrix_vpc.spoke_aws1.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RFC1918"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "spoke_aws2_vms" {
  name        = "poc-spoke-aws2-vms-sg"
  description = "SSH + HTTP + RFC1918"
  vpc_id      = aviatrix_vpc.spoke_aws2.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RFC1918"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- AWS Spoke 1 VM ---

resource "aws_instance" "spoke_aws1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.spoke_vm_instance_type
  key_name               = aws_key_pair.spoke_vms.key_name
  subnet_id              = aviatrix_vpc.spoke_aws1.subnets[0].subnet_id
  vpc_security_group_ids = [aws_security_group.spoke_vms.id]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html><html><body>
    <h1>Spoke: AWS Dublin (eu-west-1) — Spoke 1</h1>
    </body></html>
    HTML
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = {
    Name     = "spoke-aws1-vm"
    Spoke    = "aws1"
    Location = "AWS Dublin"
  }

  depends_on = [aviatrix_spoke_transit_attachment.aws1]
}

# --- AWS Spoke 2 VM ---

resource "aws_instance" "spoke_aws2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.spoke_vm_instance_type
  key_name               = aws_key_pair.spoke_vms.key_name
  subnet_id              = aviatrix_vpc.spoke_aws2.subnets[0].subnet_id
  vpc_security_group_ids = [aws_security_group.spoke_aws2_vms.id]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html><html><body>
    <h1>Spoke: AWS Dublin (eu-west-1) — Spoke 2</h1>
    </body></html>
    HTML
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = {
    Name     = "spoke-aws2-vm"
    Spoke    = "aws2"
    Location = "AWS Dublin"
  }

  depends_on = [aviatrix_spoke_transit_attachment.aws2]
}

# --- GCP Spoke VM ---

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Firewall rule on the Aviatrix-managed GCP VPC
resource "google_compute_firewall" "spoke_gcp_allow" {
  name    = "spoke-gcp-allow-ssh-http"
  network = aviatrix_vpc.spoke_gcp.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "spoke_gcp" {
  name         = "spoke-gcp-vm"
  machine_type = var.spoke_gcp_vm_type
  zone         = "${var.gcp_region}-a"
  project      = var.gcp_project_id

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }

  network_interface {
    # Use the Aviatrix-managed subnet; subnets[0] is the gateway subnet, [1] is workload
    subnetwork = aviatrix_vpc.spoke_gcp.subnets[1].subnet_id
    access_config {}
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.spoke_vms.public_key_openssh}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html><html><body>
    <h1>Spoke: GCP Paris (europe-west9)</h1>
    </body></html>
    HTML
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = ["spoke-gcp-vm"]

  depends_on = [aviatrix_spoke_transit_attachment.gcp]
}
