resource "helm_release" "postgresql" {
  name       = "postgresql"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "postgresql"
  version    = var.chart_version
  namespace  = var.namespace

  # Allow Terraform to wait until the pod is ready before marking complete
  wait    = true
  timeout = 300

  set {
    name  = "auth.database"
    value = var.db_name
  }

  set {
    name  = "auth.username"
    value = var.db_user
  }

  set_sensitive {
    name  = "auth.password"
    value = var.db_password
  }

  set_sensitive {
    # Separate postgres superuser password — must not be blank
    name  = "auth.postgresPassword"
    value = var.db_password
  }

  # Use k3s default StorageClass for local PVCs
  set {
    name  = "primary.persistence.storageClass"
    value = "local-path"
  }

  set {
    name  = "primary.persistence.size"
    value = var.storage_size
  }

  # Disable resourcesPreset so explicit primary.resources takes effect (v18 chart default is "nano")
  set {
    name  = "primary.resourcesPreset"
    value = "none"
  }

  # Resource requests
  set {
    name  = "primary.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "primary.resources.requests.memory"
    value = "256Mi"
  }

  # Resource limits
  set {
    name  = "primary.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "primary.resources.limits.memory"
    value = "512Mi"
  }
}
