# --- Gatus dashboards on EKS ---
# Two instances demonstrating DCF URL-level TLS inspection:
#   gatus-aviatrix:  monitors github.com/AviatrixSystems  → DCF PERMIT (rule 211, k8s ns smart group)
#   gatus-alexweiss: monitors github.com/alexandreweiss   → DCF DENY  (rule 212, all-pods deny)
# Both are github.com (same SNI) — URL path distinction requires TLS inspection on the spoke GW.
# Each runs in its own namespace — namespace used as k8s smart group selector for gatus-aviatrix.
#
# TLS inspection prerequisite: enable on the EKS spoke gateway via Controller UI,
# then set aviatrix_tls_ca_cert_pem in terraform.tfvars (Controller -> Settings -> Certificate -> Download CA Cert).

# --- Namespaces ---

resource "kubernetes_namespace" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  metadata { name = "gatus-aviatrix" }
}

resource "kubernetes_namespace" "gatus_alexweiss" {
  count = var.deploy_eks ? 1 : 0
  metadata { name = "gatus-alexweiss" }
}

# --- CA cert ConfigMap (shared across both namespaces) ---
# Aviatrix controller CA cert injected so pods trust the TLS inspection MITM cert.

resource "kubernetes_config_map" "aviatrix_ca_cert_aviatrix_ns" {
  count = var.deploy_eks && var.aviatrix_tls_ca_cert_pem != "" ? 1 : 0
  metadata {
    name      = "aviatrix-ca-cert"
    namespace = kubernetes_namespace.gatus_aviatrix[0].metadata[0].name
  }
  data = {
    "aviatrix-ca.crt" = var.aviatrix_tls_ca_cert_pem
  }
}

resource "kubernetes_config_map" "aviatrix_ca_cert_alexweiss_ns" {
  count = var.deploy_eks && var.aviatrix_tls_ca_cert_pem != "" ? 1 : 0
  metadata {
    name      = "aviatrix-ca-cert"
    namespace = kubernetes_namespace.gatus_alexweiss[0].metadata[0].name
  }
  data = {
    "aviatrix-ca.crt" = var.aviatrix_tls_ca_cert_pem
  }
}

# --- Gatus configs ---

resource "kubernetes_config_map" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus-config"
    namespace = kubernetes_namespace.gatus_aviatrix[0].metadata[0].name
  }
  data = {
    "config.yaml" = yamlencode({
      endpoints = [
        {
          name       = "github-aviatrixsystems"
          url        = "https://github.com/AviatrixSystems"
          interval   = "30s"
          conditions = ["[STATUS] == 200"]
        },
        {
          name       = "github-alexandreweiss"
          url        = "https://github.com/alexandreweiss"
          interval   = "30s"
          conditions = ["[STATUS] == 200"]
        },
      ]
    })
  }
}

resource "kubernetes_config_map" "gatus_alexweiss" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus-config"
    namespace = kubernetes_namespace.gatus_alexweiss[0].metadata[0].name
  }
  data = {
    "config.yaml" = yamlencode({
      endpoints = [{
        name       = "github-alexandreweiss"
        url        = "https://github.com/alexandreweiss"
        interval   = "30s"
        conditions = ["[STATUS] == 200"]
      }]
    })
  }
}

# --- Deployments ---
# When aviatrix_tls_ca_cert_pem is set: init container merges Aviatrix CA with system bundle
# into a shared volume; SSL_CERT_FILE env var points Go (Gatus) to the merged bundle.

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
        dynamic "init_container" {
          for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
          content {
            name    = "merge-ca"
            image   = "alpine:3.19"
            command = ["sh", "-c", "cat /etc/ssl/certs/ca-certificates.crt /aviatrix-ca/aviatrix-ca.crt > /shared-certs/ca-bundle.crt"]
            volume_mount {
              name       = "aviatrix-ca"
              mount_path = "/aviatrix-ca"
              read_only  = true
            }
            volume_mount {
              name       = "shared-certs"
              mount_path = "/shared-certs"
            }
          }
        }
        container {
          name  = "gatus"
          image = "twinproduction/gatus:latest"
          port { container_port = 8080 }

          dynamic "env" {
            for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
            content {
              name  = "SSL_CERT_FILE"
              value = "/shared-certs/ca-bundle.crt"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          dynamic "volume_mount" {
            for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
            content {
              name       = "shared-certs"
              mount_path = "/shared-certs"
            }
          }
        }

        volume {
          name = "config"
          config_map { name = kubernetes_config_map.gatus_aviatrix[0].metadata[0].name }
        }

        dynamic "volume" {
          for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
          content {
            name = "aviatrix-ca"
            config_map { name = kubernetes_config_map.aviatrix_ca_cert_aviatrix_ns[0].metadata[0].name }
          }
        }

        dynamic "volume" {
          for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
          content {
            name = "shared-certs"
            empty_dir {}
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "gatus_alexweiss" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus"
    namespace = kubernetes_namespace.gatus_alexweiss[0].metadata[0].name
    labels    = { app = "gatus", instance = "alexweiss" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "gatus" } }
    template {
      metadata { labels = { app = "gatus", instance = "alexweiss" } }
      spec {
        dynamic "init_container" {
          for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
          content {
            name    = "merge-ca"
            image   = "alpine:3.19"
            command = ["sh", "-c", "cat /etc/ssl/certs/ca-certificates.crt /aviatrix-ca/aviatrix-ca.crt > /shared-certs/ca-bundle.crt"]
            volume_mount {
              name       = "aviatrix-ca"
              mount_path = "/aviatrix-ca"
              read_only  = true
            }
            volume_mount {
              name       = "shared-certs"
              mount_path = "/shared-certs"
            }
          }
        }
        container {
          name  = "gatus"
          image = "twinproduction/gatus:latest"
          port { container_port = 8080 }

          dynamic "env" {
            for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
            content {
              name  = "SSL_CERT_FILE"
              value = "/shared-certs/ca-bundle.crt"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          dynamic "volume_mount" {
            for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
            content {
              name       = "shared-certs"
              mount_path = "/shared-certs"
            }
          }
        }

        volume {
          name = "config"
          config_map { name = kubernetes_config_map.gatus_alexweiss[0].metadata[0].name }
        }

        dynamic "volume" {
          for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
          content {
            name = "aviatrix-ca"
            config_map { name = kubernetes_config_map.aviatrix_ca_cert_alexweiss_ns[0].metadata[0].name }
          }
        }

        dynamic "volume" {
          for_each = var.aviatrix_tls_ca_cert_pem != "" ? [1] : []
          content {
            name = "shared-certs"
            empty_dir {}
          }
        }
      }
    }
  }
}


# --- Services ---

resource "kubernetes_service" "gatus_aviatrix" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus"
    namespace = kubernetes_namespace.gatus_aviatrix[0].metadata[0].name
  }
  spec {
    selector = { app = "gatus" }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_service" "gatus_alexweiss" {
  count = var.deploy_eks ? 1 : 0
  metadata {
    name      = "gatus-alexweiss"
    namespace = kubernetes_namespace.gatus_alexweiss[0].metadata[0].name
  }
  spec {
    selector = { app = "gatus" }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}
