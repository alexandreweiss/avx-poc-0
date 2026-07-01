# --- Gatus dashboards on EKS ---
# Two instances: one monitors aviatrix.ai, one monitors example.com
# Each runs in its own namespace — namespace used as k8s smart group selector.

resource "kubernetes_namespace" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  metadata { name = "gatus-aviatrix" }
}

resource "kubernetes_namespace" "gatus_example" {
  count = var.deploy_eks ? 1 : 0
  metadata { name = "gatus-example" }
}

resource "kubernetes_config_map" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus-config"
    namespace = kubernetes_namespace.gatus_aviatrix[0].metadata[0].name
  }
  data = {
    "config.yaml" = yamlencode({
      endpoints = [{
        name  = "aviatrix-ai"
        url   = "https://aviatrix.ai"
        interval = "30s"
        conditions = ["[STATUS] == 200"]
      }]
    })
  }
}

resource "kubernetes_config_map" "gatus_example" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus-config"
    namespace = kubernetes_namespace.gatus_example[0].metadata[0].name
  }
  data = {
    "config.yaml" = yamlencode({
      endpoints = [{
        name  = "example-com"
        url   = "https://www.example.com"
        interval = "30s"
        conditions = ["[STATUS] == 200"]
      }]
    })
  }
}

resource "kubernetes_deployment" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus"
    namespace = kubernetes_namespace.gatus_aviatrix[0].metadata[0].name
    labels    = { app = "gatus", instance = "aviatrix" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "gatus" } }
    template {
      metadata { labels = { app = "gatus", instance = "aviatrix" } }
      spec {
        container {
          name  = "gatus"
          image = "twinproduction/gatus:latest"
          port { container_port = 8080 }
          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
        }
        volume {
          name = "config"
          config_map { name = kubernetes_config_map.gatus_aviatrix[0].metadata[0].name }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "gatus_example" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus"
    namespace = kubernetes_namespace.gatus_example[0].metadata[0].name
    labels    = { app = "gatus", instance = "example" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "gatus" } }
    template {
      metadata { labels = { app = "gatus", instance = "example" } }
      spec {
        container {
          name  = "gatus"
          image = "twinproduction/gatus:latest"
          port { container_port = 8080 }
          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
        }
        volume {
          name = "config"
          config_map { name = kubernetes_config_map.gatus_example[0].metadata[0].name }
        }
      }
    }
  }
}
