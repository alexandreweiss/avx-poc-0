# Optional: GCP Partner Interconnect
# Set var.deploy_gcp_interconnect = true and provide var.gcp_interconnect_pairing_key
# when the partner circuit/pairing key is available.

resource "google_compute_router" "interconnect" {
  count   = var.deploy_gcp_interconnect ? 1 : 0
  name    = "poc-interconnect-router"
  region  = var.gcp_region
  network = module.transit_gcp.vpc.name
  project = var.gcp_project_id

  bgp {
    asn = var.gcp_interconnect_router_asn
  }
}

resource "google_compute_interconnect_attachment" "partner" {
  count     = var.deploy_gcp_interconnect ? 1 : 0
  name      = "poc-partner-interconnect"
  region    = var.gcp_region
  project   = var.gcp_project_id
  router    = google_compute_router.interconnect[0].id
  type      = "PARTNER"
  bandwidth = var.gcp_interconnect_bandwidth
}
