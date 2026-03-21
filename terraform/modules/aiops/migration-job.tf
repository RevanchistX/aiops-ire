# ─── Alembic migration Job ────────────────────────────────────────────────────
# Runs `alembic upgrade head` before the aiops-brain Deployment starts.
#
# The Job name includes a formatdate timestamp so that each `terraform apply`
# produces a fresh Kubernetes Job object rather than attempting an in-place
# update of an immutable completed Job.
#
# Execution order enforced by Terraform:
#   kubernetes_secret  →  kubernetes_job (wait_for_completion=true)
#                                        →  kubernetes_deployment
#
# On every apply Terraform will:
#   1. Attempt to delete the previous migration Job (no-op if already gone)
#   2. Create a new Job with the current timestamp in its name
#   3. Block until the Job reaches Succeeded (or fail after backoff_limit=3)
#   4. Only then proceed to reconcile the Deployment

locals {
  # formatdate produces a valid RFC 1123 lowercase name fragment, e.g. 2026-03-21-14-05-30
  migration_job_name = "aiops-brain-migrate-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}"
}

resource "kubernetes_job" "aiops_brain_migrate" {
  metadata {
    name      = local.migration_job_name
    namespace = var.namespace
    labels = {
      app        = "aiops-brain"
      component  = "migration"
      managed-by = "terraform"
    }
  }

  spec {
    # Retry up to 3 times on failure before marking the Job as failed
    backoff_limit = 3

    template {
      metadata {
        labels = {
          app       = "aiops-brain"
          component = "migration"
        }
      }

      spec {
        # Never restart the container — let the Job controller handle retries
        restart_policy = "Never"

        container {
          name    = "alembic-migrate"
          image   = var.image
          command = ["alembic", "upgrade", "head"]

          # Image loaded directly into k3s — never pull from a registry
          image_pull_policy = "Never"

          # Inject DATABASE_URL and all other env vars from the shared Secret
          env_from {
            secret_ref {
              name = kubernetes_secret.aiops_brain_env.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  # Block terraform apply until the Job reaches Succeeded status
  wait_for_completion = true

  timeouts {
    create = "5m"
    update = "5m"
  }

  depends_on = [kubernetes_secret.aiops_brain_env]
}
