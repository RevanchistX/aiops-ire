# ─── RBAC: ServiceAccount ─────────────────────────────────────────────────────
resource "kubernetes_service_account" "aiops_brain" {
  metadata {
    name      = "aiops-brain"
    namespace = var.namespace
    labels = {
      app        = "aiops-brain"
      managed-by = "terraform"
    }
  }
}

# ─── RBAC: ClusterRole ────────────────────────────────────────────────────────
# Grants the permissions needed for auto-remediation:
#   pods       — get, list, delete  (pod restart)
#   deployments — get, list, patch  (rollout restart)
resource "kubernetes_cluster_role" "aiops_brain" {
  metadata {
    name = "aiops-brain"
    labels = {
      app        = "aiops-brain"
      managed-by = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "patch"]
  }
}

# ─── RBAC: ClusterRoleBinding ─────────────────────────────────────────────────
resource "kubernetes_cluster_role_binding" "aiops_brain" {
  metadata {
    name = "aiops-brain"
    labels = {
      app        = "aiops-brain"
      managed-by = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.aiops_brain.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.aiops_brain.metadata[0].name
    namespace = var.namespace
  }
}

# ─── Secret: environment variables ────────────────────────────────────────────
# All sensitive values are injected as a Kubernetes Secret — never hardcoded.
resource "kubernetes_secret" "aiops_brain_env" {
  metadata {
    name      = "aiops-brain-env"
    namespace = var.namespace
    labels = {
      app        = "aiops-brain"
      managed-by = "terraform"
    }
  }

  # kubernetes provider auto-base64-encodes the values
  data = {
    CLAUDE_API_KEY    = var.claude_api_key
    GITHUB_TOKEN      = var.github_token
    GITHUB_REPO       = var.github_repo
    DATABASE_URL      = var.database_url
    LOKI_URL          = var.loki_url
    SLACK_WEBHOOK_URL = var.slack_webhook_url
  }
}

# ─── Deployment ───────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "aiops_brain" {
  metadata {
    name      = "aiops-brain"
    namespace = var.namespace
    labels = {
      app        = "aiops-brain"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1  # single replica — incident state lives in PostgreSQL, not memory

    selector {
      match_labels = {
        app = "aiops-brain"
      }
    }

    template {
      metadata {
        labels = {
          app = "aiops-brain"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.aiops_brain.metadata[0].name

        container {
          name  = "aiops-brain"
          image = var.image

          # Image is loaded directly into k3s — never pull from a registry
          image_pull_policy = "Never"

          port {
            container_port = 8000
            protocol       = "TCP"
          }

          # Inject all env vars from the Secret in one block
          env_from {
            secret_ref {
              name = kubernetes_secret.aiops_brain_env.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.aiops_brain,
    kubernetes_secret.aiops_brain_env,
  ]
}

# ─── Service ──────────────────────────────────────────────────────────────────
resource "kubernetes_service" "aiops_brain" {
  metadata {
    name      = "aiops-brain"
    namespace = var.namespace
    labels = {
      app        = "aiops-brain"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "aiops-brain"
    }

    port {
      name        = "http"
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
