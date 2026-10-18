# Optional: GCP Partner Interconnect (HA - 2 VLAN attachments, Orange, europe-west9)
# Set var.deploy_gcp_interconnect = true
# After apply: get both pairing keys from outputs and give to Orange.

locals {
  interconnect_advertised_cidrs = [
    var.transit_aws_cidr,
    var.transit_gcp_cidr,
    var.spoke_aws1_cidr,
    var.spoke_aws2_cidr,
    var.spoke_gcp_cidr,
  ]
}

resource "google_compute_router" "interconnect_1" {
  count   = var.deploy_gcp_interconnect ? 1 : 0
  name    = "poc-interconnect-router-1"
  region  = var.gcp_interconnect_region
  network = module.transit_gcp[0].vpc.name
  project = var.gcp_project_id

  bgp {
    asn            = 16550
    advertise_mode = "CUSTOM"

    dynamic "advertised_ip_ranges" {
      for_each = local.interconnect_advertised_cidrs
      content {
        range = advertised_ip_ranges.value
      }
    }
  }
}

resource "google_compute_router" "interconnect_2" {
  count   = var.deploy_gcp_interconnect ? 1 : 0
  name    = "poc-interconnect-router-2"
  region  = var.gcp_interconnect_region
  network = module.transit_gcp[0].vpc.name
  project = var.gcp_project_id

  bgp {
    asn            = 16550
    advertise_mode = "CUSTOM"

    dynamic "advertised_ip_ranges" {
      for_each = local.interconnect_advertised_cidrs
      content {
        range = advertised_ip_ranges.value
      }
    }
  }
}

resource "google_compute_interconnect_attachment" "partner_1" {
  count                    = var.deploy_gcp_interconnect ? 1 : 0
  name                     = "poc-partner-interconnect-1"
  region                   = var.gcp_interconnect_region
  project                  = var.gcp_project_id
  router                   = google_compute_router.interconnect_1[0].id
  type                     = "PARTNER"
  stack_type               = "IPV4_ONLY"
  edge_availability_domain = "AVAILABILITY_DOMAIN_1"
}

resource "google_compute_interconnect_attachment" "partner_2" {
  count                    = var.deploy_gcp_interconnect ? 1 : 0
  name                     = "poc-partner-interconnect-2"
  region                   = var.gcp_interconnect_region
  project                  = var.gcp_project_id
  router                   = google_compute_router.interconnect_2[0].id
  type                     = "PARTNER"
  stack_type               = "IPV4_ONLY"
  edge_availability_domain = "AVAILABILITY_DOMAIN_2"
}
