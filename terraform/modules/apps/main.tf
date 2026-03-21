# ─── Deployment ───────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "flask_app" {
  metadata {
    name      = "flask-app"
    namespace = var.namespace
    labels = {
      app        = "flask-app"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "flask-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "flask-app"
        }
      }

      spec {
        container {
          name  = "flask-app"
          image = var.image

          # Image is loaded directly into k3s — never pull from a registry
          image_pull_policy = "Never"

          port {
            container_port = 5000
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

# ─── Service ──────────────────────────────────────────────────────────────────
resource "kubernetes_service" "flask_app" {
  metadata {
    name      = "flask-app"
    namespace = var.namespace
    labels = {
      app        = "flask-app"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "flask-app"
    }

    port {
      name        = "http"
      port        = 5000
      target_port = 5000
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
