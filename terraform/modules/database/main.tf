resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }
  data = {
    password = var.db_password
  }
}

resource "kubernetes_service" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
    labels    = { app = "postgresql", managed-by = "terraform" }
  }
  spec {
    selector   = { app = "postgresql" }
    cluster_ip = "None"  # headless for StatefulSet DNS
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_stateful_set" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
    labels    = { app = "postgresql", managed-by = "terraform" }
  }

  spec {
    service_name = kubernetes_service.postgresql.metadata[0].name
    replicas     = 1

    selector {
      match_labels = { app = "postgresql" }
    }

    template {
      metadata {
        labels = { app = "postgresql" }
      }

      spec {
        container {
          name  = "postgresql"
          image = "postgres:16"

          port { container_port = 5432 }

          env {
            name  = "POSTGRES_DB"
            value = var.db_name
          }
          env {
            name  = "POSTGRES_USER"
            value = var.db_user
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgresql.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", var.db_user, "-d", var.db_name]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 6
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", var.db_user, "-d", var.db_name]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 6
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }

    volume_claim_template {
      metadata { name = "data" }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "hostpath"
        resources {
          requests = { storage = var.storage_size }
        }
      }
    }
  }
}
